local Kit = require("src.ui.game3.rse.scene_kit")
local Strings = require("src.core.Strings")
local Units = require("src.core.game3.pokedex_units")
local FrlgFont = require("src.ui.game3.frlg_font")
local RomText = require("src.core.game3.rom_text")
local Pal = require("src.core.game3.pal_fade")
local Gfx = require("src.ui.game3.rse.pokedex_gfx")
local List = require("src.ui.game3.rse.pokedex_list")
local Area = require("src.ui.game3.rse.pokedex_area")
local Cry = require("src.ui.game3.rse.pokedex_cry")
local Mapsec = require("src.ui.game3.rse.mapsec")
local RsPolicy = require("src.ui.game3.rs.pokedex_policy")
local PixelCanvas = require("src.render.PixelCanvas")
local function nativeRs() return Gfx.manifest().assetLayout == "rs" end
local rsTextNames = {gText_CryOf = "CryOf", gText_SizeComparedTo = "SizeComparedTo", gText_SelectorArrow = "RightPointingTriangle",
  gText_SearchingPleaseWait = "Searching", gText_SearchCompleted = "SearchComplete", gText_NoMatchingPkmnWereFound = "NoMatching"}
local function cached(label, copy)
  if label and RomText.has(label) then return RomText.plain(label) end
  return copy
end
local RS_LABELS = {RightPointingTriangle = "DexText_RightPointingTriangle"}
local function rsString(key)
  local copy = assert(Gfx.manifest().strings[key], "native RS dex text " .. tostring(key))
  local text = cached(RS_LABELS[key] or ("gDexText_" .. key), nil)
  if text == nil then return copy end
  return (copy:match("^\252\019.") or "") .. text
end
-- pokeruby/src/pokedex.c:4228
local function categorySuffix(unknown)
  local i, marks = 1, 0
  while i <= #unknown do
    local c = unknown:sub(i, i)
    if c == "?" then marks, i = marks + 1, i + 1
    elseif c == " " then i = i + 1
    elseif unknown:sub(i, i + 2) == "？" then marks, i = marks + 1, i + 3
    else break end
  end
  if marks == 0 or i > #unknown then return "" end
  return (unknown:sub(i - 1, i - 1) == " " and " " or "") .. unknown:sub(i)
end
local function dexText(key)
  return nativeRs() and rsString(assert(rsTextNames[key], "native RS dex text alias")) or RomText.plain(key)
end

local Pokedex = {}

Pokedex.ID = "rse_pokedex"

-- pokeemerald/src/pokedex.c:32
Pokedex.PAGE = { MAIN = 0, INFO = 1, SEARCH = 2, SEARCH_RESULTS = 3, AREA = 5, CRY = 6, SIZE = 7, CAUGHT = 8 }
-- pokeemerald/src/pokedex.c:44
Pokedex.SCREEN = { AREA = 0, CRY = 1, SIZE = 2, CANCEL = 3 }
-- pokeemerald/src/pokedex.c:53
Pokedex.SEARCH = { NAME = 0, COLOR = 1, TYPE_LEFT = 2, TYPE_RIGHT = 3, ORDER = 4, MODE = 5, OK = 6 }
Pokedex.TOPBAR = { SEARCH = 0, SHIFT = 1, CANCEL = 2 }

local PAGE, SCREEN, SEARCH, TOPBAR = Pokedex.PAGE, Pokedex.SCREEN, Pokedex.SEARCH, Pokedex.TOPBAR

-- pokeemerald/src/pokedex.c:107
local MAX_MONS_ON_SCREEN = 4
local LIST_SCROLL_STEP = 16
local POKEBALL_ROTATION_TOP = 64
local POKEBALL_ROTATION_BOTTOM = POKEBALL_ROTATION_TOP - 16
local MON_PAGE_X, MON_PAGE_Y = 48, 56
local NONE = List.NONE

Pokedex.lastSelected = 0
Pokedex.lastRotation = POKEBALL_ROTATION_TOP

local function tdiv(a, b)
  local q = a / b
  return q >= 0 and math.floor(q) or math.ceil(q)
end

local function sine(i)
  return Gfx.sine(i)
end

local function u8(v) return v % 256 end

local function se(name)
  pcall(Kit.playSe, name)
end

local function audio()
  return require("src.core.game3.audio")
end

local function constants(session)
  local Profile = require("src.core.game3.profile")
  return require("src.core.game3.constants").of(Profile.forSession(session).id)
end

local function pokemon()
  return require("src.core.game3.pokemon")
end

local entriesPack
local function entries()
  if not entriesPack then
    entriesPack = assert(Mapsec.readLua("pokemon/pokedex/entries.lua"), "pokedex entries missing from the cache")
  end
  return entriesPack
end

local regionalPack
local function regional()
  if not regionalPack then
    regionalPack = assert(Mapsec.readLua("pokemon/pokedex/regional.lua"), "regional dex pack missing from the cache")
  end
  return regionalPack
end

-- pokeemerald/src/pokemon.c:5641
function Pokedex.speciesOf(nat)
  if not nat or nat == 0 or nat == NONE then return 0 end
  return pokemon().speciesFromNational(nat) or 0
end

function Pokedex.hoennNumber(nat)
  return regional().nationalToRegional[nat]
end

local function dexFlag(s, nat, which)
  local sp = Pokedex.speciesOf(nat)
  if sp == 0 then return false end
  local Dex = require("src.core.game3.dex")
  if which == "seen" then return Dex.isSeen(s.dex, sp) end
  return Dex.isCaught(s.dex, sp)
end

function Pokedex.context(s)
  local man = Gfx.manifest()
  return {
    orders = Gfx.orders(),
    nationalEnabled = s.nationalEnabled,
    nationalCount = #Gfx.orders().numerical_national,
    seen = function(nat) return dexFlag(s, nat, "seen") end,
    owned = function(nat) return dexFlag(s, nat, "owned") end,
    hoennNumber = Pokedex.hoennNumber,
    firstChar = function(nat)
      if nativeRs() then return man.speciesFirstChar[Pokedex.speciesOf(nat)] or 0 end
      local name = pokemon().name(Pokedex.speciesOf(nat)) or ""
      return name:byte(1) or 0
    end,
    bodyColor = function(nat) return man.bodyColor[Pokedex.speciesOf(nat)] end,
    types = function(nat)
      if nativeRs() then return man.speciesTypes[Pokedex.speciesOf(nat)] end
      local t = pokemon().types(Pokedex.speciesOf(nat))
      return { t[1], t[2] }
    end,
    -- pokeemerald/include/constants/pokemon.h:5
    TYPE_NONE = 0xFF,
  }
end

-- pokeemerald/src/pokedex.c:995
local function letterRanges()
  local out = {}
  for i, r in pairs(Gfx.manifest().search.letterRanges) do
    out[i] = r
  end
  return out
end

local function nationalEnabled(session)
  local ok, Dex = pcall(require, "src.core.game3.dex")
  if not ok then return false end
  local okN, on = pcall(Dex.nationalEnabled, session)
  return okN and on == true
end

-- pokeemerald/src/pokedex.c:1540
local function newView(opts)
  local session = opts.session or {}
  local s = {
    session = session,
    dex = opts.dex or session.dex or {},
    onClose = opts.onClose,
    pal = Pal.new(),
    frames = 0,
    page = PAGE.MAIN,
    fn = "open",
    state = 0,
    list = { items = {}, count = 0 },
    selected = 0,
    selectedBackup = 0,
    dexMode = List.DEX_MODE_HOENN,
    dexModeBackup = List.DEX_MODE_HOENN,
    dexOrder = List.ORDER_NUMERICAL,
    dexOrderBackup = List.ORDER_NUMERICAL,
    monSprites = {},
    pokeBallRotation = 0,
    pokeBallRotationBackup = 0,
    pokeBallRotationStep = 0,
    initialVOffset = 0,
    scrollTimer = 0,
    scrollDirection = 0,
    listVOffset = 0,
    listMovingVOffset = 0,
    scrollMonIncrement = 0,
    maxScrollTimer = 0,
    scrollSpeed = 0,
    selectedScreen = SCREEN.AREA,
    screenSwitchState = 0,
    menuIsOpen = false,
    menuCursorPos = 0,
    menuY = 0,
    bg = {},
    sprites = {},
    rows = {},
    bgPalSet = "hoenn",
  }
  s.nationalEnabled = nationalEnabled(session)
  local pd = type(session.pokedex) == "table" and session.pokedex or {}
  s.dexMode = tonumber(pd.mode) or List.DEX_MODE_HOENN
  if not s.nationalEnabled then s.dexMode = List.DEX_MODE_HOENN end
  s.dexOrder = tonumber(pd.order) or List.ORDER_NUMERICAL
  s.selected = Pokedex.lastSelected
  s.pokeBallRotation = Pokedex.lastRotation
  s.ctx = Pokedex.context(s)
  local counts = List.counts(s.ctx)
  s.counts = counts
  if not s.nationalEnabled then
    s.seenCount, s.ownCount = counts.hoennSeen, counts.hoennOwned
  else
    s.seenCount, s.ownCount = counts.nationalSeen, counts.nationalOwned
  end
  s.initialVOffset = 8
  return s
end
Pokedex.newView = newView

local function createList(s)
  s.list = List.create(s.ctx, s.dexMode, s.dexOrder)
end

local function item(s, i)
  return List.item(s.list, i)
end

local function paletteSet(s)
  if s.isSearchResults then return "searchResults" end
  if not s.nationalEnabled then return "hoenn" end
  return "national"
end

local function bgPal(s)
  return Gfx.bgPalette(paletteSet(s))
end

-- Read-only bg palettes for per-frame draws, rebuilt when the manifest
-- changes.  bgPal returns a fresh copy for callers that edit it.
local _readPals, _readPalsMan = {}, nil
local function bgPalRead(s)
  local man = Gfx.manifest()
  if man ~= _readPalsMan then
    _readPals, _readPalsMan = {}, man
  end
  local set = paletteSet(s)
  local pal = _readPals[set]
  if not pal then
    pal = Gfx.bgPalette(set)
    _readPals[set] = pal
  end
  return pal
end

local function textColors(s, fgIdx, shIdx)
  local pal = bgPalRead(s)
  if nativeRs() then
    local w = Gfx.manifest().windows[(s.page == PAGE.CRY or s.page == PAGE.SIZE) and "cry" or "info"]
    return {fg = Gfx.color(pal[w.paletteNum * 16 + w.foreground]), shadow = Gfx.color(pal[w.paletteNum * 16 + w.shadow]),
      bg = w.background == 0 and {0, 0, 0, 0} or Gfx.color(pal[w.paletteNum * 16 + w.background])}
  end
  return { fg = Gfx.color(pal[fgIdx or 15]), shadow = Gfx.color(pal[shIdx or 3]), bg = { 0, 0, 0, 0 } }
end
function Pokedex.textOptions(s) return {colors = textColors(s), font = "normal"} end

local function spritePal()
  local p = Gfx.manifest().palettes.hoenn
  local out = {}
  for i = 1, 16 do out[i] = p[i] end
  return out
end

-- pokeemerald/src/pokedex.c:678
local function interfaceSprite(tile, w, h)
  return Gfx.sprite("interface", tile, w, h, spritePal())
end

local function layer(key, img, prio, hofs, vofs)
  return { key = key, img = img, prio = prio, hofs = hofs or 0, vofs = vofs or 0, visible = true }
end

-- pokeemerald/src/pokedex.c:2743
local function spriteDexNum(s, i)
  if i < 0 or i >= 386 then return NONE end
  local it = s.list.items[i]
  if not it then return NONE end
  if it.seen then return it.dexNum end
  return 0
end

local function monPic(s, dexNum)
  local P = pokemon()
  local sp = Pokedex.speciesOf(dexNum)
  -- pokeemerald/src/data/pokemon_graphics/front_pic_table.h:3
  if sp == 0 then return Kit.rgbaImage("data/generated/gba/pokemon/front/0.rgba", 64, 64) end
  local personality = 0
  local dex = s.dex or {}
  local C = constants(s.session)
  -- pokeemerald/src/pokedex.c:4654
  if sp == C.species.byName.SPECIES_UNOWN then personality = tonumber(dex.unownPersonality) or 0 end
  if sp == C.species.byName.SPECIES_SPINDA then personality = tonumber(dex.spindaPersonality) or 0 end
  local entry = P.frontPic(P.picSpecies(sp, personality), nil, false, personality, "dex")
  return entry and entry.image or nil
end

local function createMonSprite(s, dexNum, x, y)
  for i = 0, MAX_MONS_ON_SCREEN - 1 do
    if not s.monSprites[i] then
      local spr = { dexNum = dexNum, img = monPic(s, dexNum), x = x, y = y, x2 = 0, y2 = 0, data0 = 0, slot = i,
        data5 = 0, prio = 3, affine = true, invisible = false, cb = "list" }
      s.monSprites[i] = spr
      return spr
    end
  end
  return nil
end

local function clearMonSprites(s)
  s.monSprites = {}
end

-- pokeemerald/src/pokedex.c:2323
local function setRow(s, row, entryNum)
  local vrow = row % 32
  if entryNum < 0 or entryNum >= 386 then
    s.rows[vrow] = nil
    return
  end
  local it = s.list.items[entryNum]
  if not it then
    s.rows[vrow] = nil
    return
  end
  local num = it.dexNum
  if s.dexMode == List.DEX_MODE_HOENN then num = Pokedex.hoennNumber(num) or num end
  local name
  if it.seen then
    name = pokemon().name(Pokedex.speciesOf(it.dexNum))
  else
    name = Gfx.manifest().tenDashes
  end
  s.rows[vrow] = { num = string.format("%03d", num), owned = it.seen and it.owned, name = name }
end

-- pokeemerald/src/pokedex.c:2334
local function createMonListEntry(s, position, b)
  if position == 0 then
    local entryNum = b - 5
    for i = 0, 10 do
      setRow(s, i * 2, entryNum)
      entryNum = entryNum + 1
    end
  elseif position == 1 then
    setRow(s, s.listVOffset * 2, b - 5)
  elseif position == 2 then
    local v = s.listVOffset + 10
    if v >= LIST_SCROLL_STEP then v = v - LIST_SCROLL_STEP end
    setRow(s, v * 2, b + 5)
  end
end

-- pokeemerald/src/pokedex.c:2465
local function createMonSpritesAtPos(s, selectedMon)
  s.monSprites = {}
  local d = spriteDexNum(s, selectedMon - 1)
  if d ~= NONE then createMonSprite(s, d, 0x60, 0x50).data5 = -32 end
  d = spriteDexNum(s, selectedMon)
  if d ~= NONE then createMonSprite(s, d, 0x60, 0x50).data5 = 0 end
  d = spriteDexNum(s, selectedMon + 1)
  if d ~= NONE then createMonSprite(s, d, 0x60, 0x50).data5 = 32 end
  s.rows = {}
  createMonListEntry(s, 0, selectedMon)
  s.bg2vofs = s.initialVOffset
  s.listVOffset = 0
  s.listMovingVOffset = 0
end

-- pokeemerald/src/pokedex.c:2513
local function updateDexListScroll(s, direction, inc, timerMax)
  if s.scrollTimer > 0 then
    s.scrollTimer = s.scrollTimer - 1
    local step = tdiv(LIST_SCROLL_STEP * (timerMax - s.scrollTimer), timerMax)
    if direction == 1 then
      for i = 0, MAX_MONS_ON_SCREEN - 1 do
        if s.monSprites[i] then s.monSprites[i].data5 = s.monSprites[i].data5 + inc end
      end
      s.bg2vofs = s.initialVOffset + s.listMovingVOffset * LIST_SCROLL_STEP - step
      s.pokeBallRotation = u8(s.pokeBallRotation - s.pokeBallRotationStep)
    else
      for i = 0, MAX_MONS_ON_SCREEN - 1 do
        if s.monSprites[i] then s.monSprites[i].data5 = s.monSprites[i].data5 - inc end
      end
      s.bg2vofs = s.initialVOffset + s.listMovingVOffset * LIST_SCROLL_STEP + step
      s.pokeBallRotation = u8(s.pokeBallRotation + s.pokeBallRotationStep)
    end
    return false
  end
  s.bg2vofs = s.initialVOffset + s.listVOffset * LIST_SCROLL_STEP
  return true
end

-- pokeemerald/src/pokedex.c:2553
local function createScrollingSprite(s, direction, selectedMon)
  s.listMovingVOffset = s.listVOffset
  if direction == 1 then
    local d = spriteDexNum(s, selectedMon - 1)
    if d ~= NONE then
      local spr = createMonSprite(s, d, 0x60, 0x50)
      if spr then spr.data5 = -64 end
    end
    if s.listVOffset > 0 then s.listVOffset = s.listVOffset - 1 else s.listVOffset = LIST_SCROLL_STEP - 1 end
  else
    local d = spriteDexNum(s, selectedMon + 1)
    if d ~= NONE then
      local spr = createMonSprite(s, d, 0x60, 0x50)
      if spr then spr.data5 = 64 end
    end
    if s.listVOffset < LIST_SCROLL_STEP - 1 then s.listVOffset = s.listVOffset + 1 else s.listVOffset = 0 end
  end
end

-- pokeemerald/src/pokedex.c:4624
local function nextPosition(direction, pos, min, max)
  if direction == 1 then
    if pos > min then pos = pos - 1 end
  elseif direction == 0 then
    if pos < max then pos = pos + 1 end
  end
  return pos
end

-- pokeemerald/src/pokedex.c:2591
local function tryDoPokedexScroll(s, inp, selectedMon)
  local held, new = inp.held or {}, inp.new or {}
  local dir = 0
  local last = s.list.count - 1
  if held.up and selectedMon > 0 then
    dir = 1
    selectedMon = nextPosition(1, selectedMon, 0, last)
    createScrollingSprite(s, 1, selectedMon)
    createMonListEntry(s, 1, selectedMon)
    se("SE_DEX_SCROLL")
  elseif held.down and selectedMon < last then
    dir = 2
    selectedMon = nextPosition(0, selectedMon, 0, last)
    createScrollingSprite(s, 2, selectedMon)
    createMonListEntry(s, 2, selectedMon)
    se("SE_DEX_SCROLL")
  elseif new.left and selectedMon > 0 then
    local start = selectedMon
    for _ = 1, 7 do selectedMon = nextPosition(1, selectedMon, 0, last) end
    s.pokeBallRotation = u8(s.pokeBallRotation + 16 * (selectedMon - start))
    clearMonSprites(s)
    createMonSpritesAtPos(s, selectedMon)
    se("SE_DEX_PAGE")
  elseif new.right and selectedMon < last then
    local start = selectedMon
    for _ = 1, 7 do selectedMon = nextPosition(0, selectedMon, 0, last) end
    s.pokeBallRotation = u8(s.pokeBallRotation + 16 * (selectedMon - start))
    clearMonSprites(s)
    createMonSpritesAtPos(s, selectedMon)
    se("SE_DEX_PAGE")
  end
  if dir == 0 then
    s.scrollSpeed = 0
    return selectedMon
  end
  local man = Gfx.manifest()
  local inc = man.scrollMonIncrements[math.floor(s.scrollSpeed / 4) + 1]
  local timer = man.scrollTimers[math.floor(s.scrollSpeed / 4) + 1]
  s.scrollTimer = timer
  s.maxScrollTimer = timer
  s.scrollMonIncrement = inc
  s.scrollDirection = dir
  s.pokeBallRotationStep = math.floor(inc / 2)
  updateDexListScroll(s, dir, inc, timer)
  if s.scrollSpeed < 12 then s.scrollSpeed = s.scrollSpeed + 1 end
  return selectedMon
end

local function selectedMonSprite(s)
  for i = 0, MAX_MONS_ON_SCREEN - 1 do
    local spr = s.monSprites[i]
    if spr and spr.x2 == 0 and spr.y2 == 0 then return spr end
  end
  return nil
end

-- pokeemerald/src/pokedex.c:2670
local function tryDoInfoScreenScroll(s, inp)
  local new = inp.new or {}
  local sel = s.selected
  local last = s.list.count - 1
  if new.up and sel > 0 then
    local nextMon = sel
    while nextMon ~= 0 do
      nextMon = nextPosition(1, nextMon, 0, last)
      if item(s, nextMon).seen then
        sel = nextMon
        break
      end
    end
    if s.selected == sel then return false end
    s.selected = sel
    s.pokeBallRotation = u8(s.pokeBallRotation - 16)
    return true
  elseif new.down and sel < last then
    local nextMon = sel
    while nextMon < last do
      nextMon = nextPosition(0, nextMon, 0, last)
      if item(s, nextMon).seen then
        sel = nextMon
        break
      end
    end
    if s.selected == sel then return false end
    s.selected = sel
    s.pokeBallRotation = u8(s.pokeBallRotation + 16)
    return true
  end
  return false
end

-- pokeemerald/src/pokedex.c:2777
local function createInterfaceSprites(s, page)
  if nativeRs() then s.sprites = RsPolicy.interfaceSprites(s, page); return end
  local sp = {}
  local function add(t) sp[#sp + 1] = t; return t end
  add({ kind = "arrow", tile = 1, w = 16, h = 8, x = 184, y = 4, prio = 0, down = false, data2 = 0 })
  add({ kind = "arrow", tile = 1, w = 16, h = 8, x = 184, y = 160 - 4, prio = 0, down = true, vflip = true, data2 = 0 })
  add({ kind = "scrollbar", tile = 3, w = 8, h = 8, x = 230, y = 20, prio = 1 })
  add({ kind = "text", tile = 48, w = 32, h = 16, x = 16, y = 120, prio = 0 })
  add({ kind = "text", tile = 56, w = 32, h = 16, x = 48, y = 120, prio = 0 })
  add({ kind = "text", tile = 32, w = 32, h = 16, x = 16, y = 160 - 16, prio = 0 })
  add({ kind = "text", tile = 40, w = 32, h = 16, x = 48, y = 160 - 16, prio = 0 })
  add({ kind = "ball", tile = 16, w = 32, h = 32, x = 0, y = 80, prio = 1, data1 = 0, objwin = true })
  add({ kind = "ball", tile = 16, w = 32, h = 32, x = 0, y = 80, prio = 1, data1 = 128, objwin = true })
  if page == PAGE.MAIN then
    local function digits(count, x, y, base)
      local d100 = math.floor(count / 100)
      local draw = d100 ~= 0
      add({ kind = "seen", tile = base + 2 * d100, w = 8, h = 16, x = x, y = y, prio = 0, invisible = d100 == 0 })
      local d10 = math.floor((count % 100) / 10)
      add({ kind = "seen", tile = base + 2 * ((d10 ~= 0 or draw) and d10 or 0), w = 8, h = 16, x = x + 8, y = y,
        prio = 0, invisible = not (d10 ~= 0 or draw) })
      add({ kind = "seen", tile = base + 2 * (count % 10), w = 8, h = 16, x = x + 16, y = y, prio = 0 })
    end
    if not s.nationalEnabled then
      add({ kind = "seen", tile = 64, w = 64, h = 32, x = 32, y = 40, prio = 0 })
      add({ kind = "seen", tile = 96, w = 64, h = 32, x = 32, y = 72, prio = 0 })
      digits(s.seenCount, 24, 48, 128)
      digits(s.ownCount, 24, 80, 128)
    else
      add({ kind = "seen", tile = 64, w = 64, h = 32, x = 32, y = 40, prio = 0 })
      add({ kind = "seen", tile = 96, w = 64, h = 32, x = 32, y = 76, prio = 0 })
      add({ kind = "seen", tile = 160, w = 32, h = 16, x = 17, y = 45, prio = 0 })
      add({ kind = "seen", tile = 168, w = 32, h = 16, x = 17, y = 55, prio = 0 })
      add({ kind = "seen", tile = 160, w = 32, h = 16, x = 17, y = 81, prio = 0 })
      add({ kind = "seen", tile = 168, w = 32, h = 16, x = 17, y = 91, prio = 0 })
      digits(s.counts.hoennSeen, 40, 45, 176)
      digits(s.seenCount, 40, 55, 176)
      digits(s.counts.hoennOwned, 40, 81, 176)
      digits(s.ownCount, 40, 91, 176)
    end
    add({ kind = "cursor", tile = 4, w = 8, h = 16, x = 136, y = 96, prio = 0, invisible = true, data2 = 0 })
  else
    add({ kind = "cursor", tile = 4, w = 8, h = 16, x = 136, y = 80, prio = 0, invisible = true, data2 = 0 })
  end
  s.sprites = sp
end

local function onListPage(s)
  return s.page == PAGE.MAIN or s.page == PAGE.SEARCH_RESULTS
end

-- pokeemerald/src/pokedex.c:3037
local function animateSprites(s)
  local listPage = onListPage(s)
  for _, spr in ipairs(s.sprites) do
    if spr.kind == "arrow" then
      spr.invisible = spr.down and (s.selected == s.list.count - 1) or (not spr.down and s.selected == 0)
      local r0 = spr.down and spr.data2 or (spr.data2 - 128)
      spr.y2 = tdiv(sine(u8(r0)), 64)
      spr.data2 = u8(spr.data2 + 8)
      if s.menuIsOpen or s.menuY ~= 0 then spr.invisible = true end
    elseif spr.kind == "scrollbar" then
      spr.y2 = s.list.count > 1 and tdiv(s.selected * 120, s.list.count - 1) or 0
    elseif spr.kind == "ball" then
      local val = u8(s.pokeBallRotation + spr.data1)
      spr.rot = val
      local v2 = u8(s.pokeBallRotation + spr.data1 + 64)
      spr.x2 = tdiv(sine(v2 + 64) * 40, 256)
      spr.y2 = tdiv(sine(v2) * 40, 256)
    elseif spr.kind == "cursor" then
      local r1 = s.page == PAGE.MAIN and 80 or 96
      if s.menuIsOpen and s.menuY == r1 then
        spr.invisible = false
        spr.y2 = s.menuCursorPos * 16
        spr.x2 = tdiv(sine(u8(spr.data2)), 64)
        spr.data2 = u8(spr.data2 + 8)
      else
        spr.invisible = true
      end
    end
  end
  if not listPage then s.sprites = {} end
  for i = 0, MAX_MONS_ON_SCREEN - 1 do
    local spr = s.monSprites[i]
    if spr and spr.cb == "list" then
      if not listPage then
        s.monSprites[i] = nil
      else
        spr.y2 = tdiv(sine(u8(spr.data5)) * 76, 256)
        local c = sine(u8(spr.data5 + 64))
        spr.scaleY = c > 0 and math.max(1 / 256, c / 256) or 0
        if spr.data5 > -64 and spr.data5 < 64 then
          spr.invisible = false
          spr.data0 = 1
        else
          spr.invisible = true
        end
        if (spr.data5 <= -64 or spr.data5 >= 64) and spr.data0 ~= 0 then s.monSprites[i] = nil end
      end
    elseif spr and spr.cb == "moveToInfo" then
      -- pokeemerald/src/pokedex.c:3013
      spr.prio = 0
      spr.affine = false
      spr.scaleY = 1
      spr.x2, spr.y2 = 0, 0
      if spr.x ~= MON_PAGE_X or spr.y ~= MON_PAGE_Y then
        if spr.x > MON_PAGE_X then spr.x = spr.x - 1 end
        if spr.x < MON_PAGE_X then spr.x = spr.x + 1 end
        if spr.y > MON_PAGE_Y then spr.y = spr.y - 1 end
        if spr.y < MON_PAGE_Y then spr.y = spr.y + 1 end
      else
        spr.cb = nil
      end
    elseif spr and spr.cb == "slideToCenter" then
      -- pokeemerald/src/pokedex.c:4079
      if spr.x < 120 then spr.x = spr.x + 2 end
      if spr.x > 120 then spr.x = spr.x - 2 end
      if spr.y < 80 then spr.y = spr.y + 1 end
      if spr.y > 80 then spr.y = spr.y - 1 end
    end
  end
end

-- pokeemerald/src/pokedex.c:2053
local function loadListPage(s, page)
  local st = s.state
  if st == 0 then
    if s.pal:fadeActive() then return false end
    s.page = page
    s.isSearchResults = page ~= PAGE.MAIN
    local pal = bgPal(s)
    s.bg = {
      [3] = layer("list_underlay", Gfx.renderMap(Gfx.map("list_underlay"), "menu", pal), 3),
      [1] = layer("list", Gfx.renderMap(Gfx.map("list"), "menu", pal), 1),
      [0] = layer("start_menu", nil, 0),
    }
    local menuKey = page == PAGE.MAIN and "start_menu_main" or "start_menu_search"
    local menu = Gfx.map(menuKey)
    local full = { n = 32 * 32 }
    for i = 0, full.n - 1 do full[i] = 0 end
    for i = 0, menu.n - 1 do full[0x280 + i] = menu[i] end
    s.bg[0].img = Gfx.renderMap(full, "menu", pal, { rows = 32 })
    s.bg2vofs = s.initialVOffset
    s.state = 1
  elseif st == 1 then
    createInterfaceSprites(s, page)
    s.state = 2
  elseif st == 2 then
    s.state = 3
  elseif st == 3 then
    if page == PAGE.MAIN then createList(s) end
    createMonSpritesAtPos(s, s.selected)
    s.menuIsOpen = false
    s.menuY = 0
    s.state = 4
  elseif st == 4 then
    s.pal:beginFade(Pal.ALL, 0, 16, 0, Pal.BLACK)
    s.state = 5
  elseif st == 5 then
    s.shown = true
    s.state = 6
  elseif st == 6 then
    if not s.pal:fadeActive() then
      s.state = 0
      return true
    end
  end
  return false
end

local function closeDex(s)
  local session = s.session
  session.pokedex = type(session.pokedex) == "table" and session.pokedex or {}
  session.pokedex.mode = s.nationalEnabled and s.dexMode or List.DEX_MODE_HOENN
  session.pokedex.order = s.dexOrder
  local Stack = require("src.ui.game3.stack")
  Pokedex.Host._s = nil
  Stack.pop(Pokedex.ID)
  if s.onClose then s.onClose() end
end

local tasks = {}

-- pokeemerald/src/pokedex.c:1591
function tasks.open(s)
  if s.state < 3 then
    s.state = s.state + 1
    if s.state == 3 then
      createList(s)
      s.state = 0
      s.fn = "openMain"
    end
  end
end

-- pokeemerald/src/pokedex.c:1656
function tasks.openMain(s)
  s.isSearchResults = false
  if loadListPage(s, PAGE.MAIN) then s.fn = "mainInput" end
end

function tasks.openSearchResults(s)
  s.isSearchResults = true
  if loadListPage(s, PAGE.SEARCH_RESULTS) then s.fn = "mainInput" end
end

local function listInput(s, inp)
  local new = inp.new or {}
  if s.menuY ~= 0 then
    s.menuY = s.menuY - 8
    return
  end
  local resultsPage = s.page == PAGE.SEARCH_RESULTS
  if new.a and item(s, s.selected).seen then
    local spr = selectedMonSprite(s)
    s.movingMon = spr
    if spr then spr.cb = "moveToInfo" end
    s.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
    s.fadeExempt = { mon = true }
    s.fn = "openInfoAfterMove"
    se("SE_PIN")
  elseif new.start then
    s.menuY = 0
    s.menuIsOpen = true
    s.menuCursorPos = 0
    s.fn = "startMenu"
    se("SE_SELECT")
  elseif new.select then
    se("SE_SELECT")
    s.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
    s.screenSwitchState = 0
    if not resultsPage then
      s.pokeBallRotationBackup = s.pokeBallRotation
      s.selectedBackup = s.selected
      s.dexModeBackup = s.dexMode
      s.dexOrderBackup = s.dexOrder
    end
    s.search = { state = 0 }
    s.fn = "loadSearch"
    s.state = 0
    se("SE_PC_LOGIN")
  elseif new.b then
    s.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
    s.fn = resultsPage and "returnFromResults" or "close"
    se("SE_PC_OFF")
  else
    s.selected = tryDoPokedexScroll(s, inp, s.selected)
    if s.scrollTimer > 0 then s.fn = "waitScroll" end
  end
end

-- pokeemerald/src/pokedex.c:1665
function tasks.mainInput(s, inp)
  listInput(s, inp)
end

-- pokeemerald/src/pokedex.c:1722
function tasks.waitScroll(s)
  if updateDexListScroll(s, s.scrollDirection, s.scrollMonIncrement, s.maxScrollTimer) then
    s.fn = "mainInput"
  end
end

-- pokeemerald/src/pokedex.c:1728
function tasks.startMenu(s, inp)
  local new = inp.new or {}
  local results = s.page == PAGE.SEARCH_RESULTS
  local target = results and 96 or 80
  local last = results and 4 or 3
  if s.menuY ~= target then
    s.menuY = s.menuY + 8
    return
  end
  local exit = false
  if new.a then
    local c = s.menuCursorPos
    if c == 1 then
      s.selected = 0
      s.pokeBallRotation = POKEBALL_ROTATION_TOP
      clearMonSprites(s)
      createMonSpritesAtPos(s, s.selected)
      exit = true
    elseif c == 2 then
      s.selected = s.list.count - 1
      s.pokeBallRotation = u8(s.list.count * 16 + POKEBALL_ROTATION_BOTTOM)
      clearMonSprites(s)
      createMonSpritesAtPos(s, s.selected)
      exit = true
    elseif c == 3 and results then
      s.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
      s.fn = "returnFromResults"
      se("SE_TRUCK_DOOR")
    elseif c == last then
      s.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
      s.fn = results and "closeFromResults" or "close"
      se("SE_PC_OFF")
    else
      exit = true
    end
  end
  if exit or new.start or new.b then
    s.menuIsOpen = false
    s.fn = "mainInput"
    se("SE_SELECT")
  elseif (inp.rep or {}).up and s.menuCursorPos ~= 0 then
    s.menuCursorPos = s.menuCursorPos - 1
    se("SE_SELECT")
  elseif (inp.rep or {}).down and s.menuCursorPos < last then
    s.menuCursorPos = s.menuCursorPos + 1
    se("SE_SELECT")
  end
end

-- pokeemerald/src/pokedex.c:1844
function tasks.close(s)
  if not s.pal:fadeActive() then
    Pokedex.lastSelected = s.selected
    Pokedex.lastRotation = s.pokeBallRotation
    closeDex(s)
  end
end

-- pokeemerald/src/pokedex.c:2020
function tasks.returnFromResults(s)
  if not s.pal:fadeActive() then
    s.pokeBallRotation = s.pokeBallRotationBackup
    s.selected = s.selectedBackup
    s.dexMode = s.nationalEnabled and s.dexModeBackup or List.DEX_MODE_HOENN
    s.dexOrder = s.dexOrderBackup
    clearMonSprites(s)
    s.state = 0
    s.fn = "openMain"
  end
end

-- pokeemerald/src/pokedex.c:2036
function tasks.closeFromResults(s)
  if not s.pal:fadeActive() then
    s.pokeBallRotation = s.pokeBallRotationBackup
    s.selected = s.selectedBackup
    s.dexMode = s.nationalEnabled and s.dexModeBackup or List.DEX_MODE_HOENN
    s.dexOrder = s.dexOrderBackup
    s.fn = "close"
  end
end

-- pokeemerald/src/pokedex.c:1790
function tasks.openInfoAfterMove(s)
  local spr = s.movingMon
  if not spr or (spr.x == MON_PAGE_X and spr.y == MON_PAGE_Y) then
    s.pageBackup = s.page
    s.info = { scrolling = false, monDone = spr ~= nil, bgLoaded = false, skipCry = false, mon = spr }
    s.fn = "loadInfo"
    s.state = 0
  end
end

local function entryFor(nat)
  return entries()[Pokedex.speciesOf(nat)] or entries()[0] or {}
end

-- pokeemerald/src/pokedex.c:4154
function Pokedex.heightText(height)
  local inches = math.floor(height * 10000 / 254)
  if inches % 10 >= 5 then inches = inches + 10 end
  local feet = math.floor(inches / 120)
  inches = math.floor((inches - feet * 120) / 10)
  local clearTo = (math.floor(feet / 10) == 0) and 18 or 12
  return string.char(0xFC, 0x13, clearTo) .. tostring(feet) .. "'" .. string.format("%02d", inches) .. "\""
end

-- pokeemerald/src/pokedex.c:4187
function Pokedex.weightText(weight)
  local lbs = math.floor(weight * 100000 / 4536)
  if lbs % 10 >= 5 then lbs = lbs + 10 end
  local out, output = {}, false
  local function digit(d)
    if d == 0 and not output then
      out[#out + 1] = "{UNK_SPACER}"
    else
      output = true
      out[#out + 1] = tostring(d)
    end
  end
  digit(math.floor(lbs / 100000))
  lbs = lbs % 100000
  digit(math.floor(lbs / 10000))
  lbs = lbs % 10000
  digit(math.floor(lbs / 1000))
  lbs = lbs % 1000
  out[#out + 1] = tostring(math.floor(lbs / 100))
  lbs = lbs % 100
  out[#out + 1] = "." .. tostring(math.floor(lbs / 10)) .. " lbs."
  return table.concat(out)
end

-- pokeemerald/src/pokedex.c:4102
local function monInfo(s, nat, nationalNumber, owned, newEntry)
  local e = entryFor(nat)
  if nativeRs() then
    local out = {}
    if newEntry then
      local t = rsString("RegisterComplete")
      out[#out + 1] = {text = t, x = 16 + math.floor((208 - FrlgFont.measure(t)) / 2), y = 0}
    end
    local num = nationalNumber and nat or (Pokedex.hoennNumber(nat) or nat)
    out[#out + 1] = {text = string.format("%03d", num), x = 104, y = 24}
    out[#out + 1] = {text = pokemon().name(Pokedex.speciesOf(nat)) or Gfx.manifest().tenDashes, x = 128, y = 24}
    local unknown = rsString("UnknownPoke")
    local category = owned and (Strings(e.category or "") .. categorySuffix(unknown)) or unknown
    local cx = 88 + (owned and (FrlgFont.measure(unknown) - FrlgFont.measure(category)) or 0)
    out[#out + 1] = {text = category, x = cx, y = 40}
    local metric = owned and Units.metric(Pokedex.speciesOf(nat))
    out[#out + 1] = {text = metric and Units.height(metric, "  ") or owned and Pokedex.heightText(e.height or 0) or rsString("UnknownHeight"), x = 128, y = 56}
    out[#out + 1] = {text = metric and Units.weight(metric, "  ") or owned and RsPolicy.weightText(e.weight or 0) or rsString("UnknownWeight"), x = 128, y = 72}
    local desc
    if s.descriptionPage == 1 then
      desc = cached(e.descriptionLabel2, e.description2)
    else
      desc = cached(e.descriptionLabel, e.description)
    end
    out[#out + 1] = {text = owned and (desc or "") or "", x = 16, y = 104}
    return out
  end
  local out = {}
  if newEntry then
    local t = RomText.plain("gText_PokedexRegistration")
    out[#out + 1] = { text = t, x = math.max(0, math.floor((240 - (FrlgFont.measure(t) or 0)) / 2)), y = 0 }
  end
  local num = nationalNumber and nat or (Pokedex.hoennNumber(nat) or nat)
  out[#out + 1] = { text = RomText.plain("gText_NumberClear01") .. string.format("%03d", num), x = 0x60, y = 0x19 }
  local sp = Pokedex.speciesOf(nat)
  out[#out + 1] = { text = sp ~= 0 and pokemon().name(sp) or Gfx.manifest().tenDashes, x = 0x84, y = 0x19 }
  local category
  if owned then
    category = Strings(e.category or "") .. " " .. RomText.plain("gText_Pokemon")
  else
    category = RomText.plain("gText_5MarksPokemon")
  end
  out[#out + 1] = { text = category, x = 0x64, y = 0x29 }
  out[#out + 1] = { text = RomText.plain("gText_HTHeight"), x = 0x60, y = 0x39 }
  out[#out + 1] = { text = RomText.plain("gText_WTWeight"), x = 0x60, y = 0x49 }
  local metric = owned and Units.metric(sp)
  if metric then
    out[#out + 1] = { text = Units.height(metric, "{UNK_SPACER}"), x = 0x81, y = 0x39 }
    out[#out + 1] = { text = Units.weight(metric, "{UNK_SPACER}"), x = 0x81, y = 0x49 }
  elseif owned then
    out[#out + 1] = { text = Pokedex.heightText(e.height or 0), x = 0x81, y = 0x39 }
    out[#out + 1] = { text = Pokedex.weightText(e.weight or 0), x = 0x81, y = 0x49 }
  else
    out[#out + 1] = { text = RomText.plain("gText_UnkHeight"), x = 0x81, y = 0x39 }
    out[#out + 1] = { text = RomText.plain("gText_UnkWeight"), x = 0x81, y = 0x49 }
  end
  local desc = owned and Strings(e.description or "") or ""
  local w = 0
  for line in (desc .. "\n"):gmatch("(.-)\n") do w = math.max(w, FrlgFont.measure(line) or 0) end
  out[#out + 1] = { text = desc, x = w < 240 and math.floor((240 - w) / 2) or 0, y = 95 }
  return out
end
Pokedex.monInfo = monInfo

-- pokeemerald/src/pokedex.c:3880
local function selectBar(s, submenu, selected)
  local m = Gfx.map(submenu and "select_sub" or "select_main")
  local width = nativeRs() and 5 or 7
  for i = 0, 3 do
    local row = i * width + 1
    local pal
    if submenu then
      pal = (i == selected or i == (nativeRs() and 0 or 3)) and 2 or 4
    else
      pal = (i == selected) and 2 or 4
    end
    for j = 0, width - 1 do
      m[row + j] = m[row + j] % 4096 + pal * 4096
      m[row + j + 32] = m[row + j + 32] % 4096 + pal * 4096
    end
  end
  if nativeRs() then for j = 25, 29 do for _, off in ipairs({0, 32}) do m[j + off] = m[j + off] % 4096 + 4 * 4096 end end end
  return layer("select", Gfx.renderMap(m, "menu", bgPal(s)), 0)
end

local function footprintImage(nat)
  local sp = Pokedex.speciesOf(nat)
  local img = Kit.rgbaImage("data/generated/gba/pokemon/footprints/" .. sp .. ".rgba", 16, 16)
  return img
end

-- pokeemerald/src/pokedex.c:3231
function tasks.loadInfo(s)
  local st = s.state
  local info = s.info
  if st == 0 then
    if not s.pal:fadeActive() then
      s.page = PAGE.INFO
      if nativeRs() then s.descriptionPage = 0 end
      s.state = 1
    end
  elseif st == 1 then
    local it = item(s, s.selected)
    info.dexNum = it.dexNum
    info.owned = it.owned
    s.state = 2
  elseif st == 2 then
    local pal = bgPal(s)
    if not info.owned then
      for i = 1, 15 do pal[48 + i] = pal[i] end
    end
    s.bg = {
      [3] = layer("info", Gfx.renderMap(Gfx.map("info"), "menu", pal), 2),
      [1] = selectBar(s, false, s.selectedScreen),
    }
    s.bg[1].prio = 0
    s.state = 3
  elseif st == 3 then
    s.state = 4
  elseif st == 4 then
    info.text = monInfo(s, info.dexNum, s.dexMode ~= List.DEX_MODE_HOENN, info.owned, false)
    info.footprint = (not nativeRs() or info.owned) and footprintImage(info.dexNum) or nil
    s.state = 5
  elseif st == 5 then
    if not info.monDone then
      info.mon = { dexNum = info.dexNum, img = monPic(s, info.dexNum), x = MON_PAGE_X, y = MON_PAGE_Y, x2 = 0, y2 = 0,
        prio = 0, affine = false, scaleY = 1 }
    end
    s.monSprites = { [0] = info.mon }
    s.state = 6
  elseif st == 6 then
    s.fadeExempt = { mon = info.monDone, select = info.bgLoaded }
    s.pal:beginFade(Pal.ALL, 0, 16, 0, Pal.BLACK)
    s.state = 7
  elseif st == 7 then
    s.shown = true
    s.state = 8
  elseif st == 8 then
    if not s.pal:fadeActive() then
      s.fadeExempt = nil
      s.state = 9
      if not info.skipCry then
        audio().stopCry()
        audio().playCry(Pokedex.speciesOf(info.dexNum), { noDuck = true })
      else
        s.state = 10
      end
    end
  elseif st == 9 then
    if audio().isCryFinished() then s.state = 10 end
  elseif st == 10 then
    info.scrolling = false
    info.monDone = false
    info.bgLoaded = true
    info.skipCry = true
    s.fn = "infoInput"
    s.state = 0
  end
end

-- pokeemerald/src/pokedex.c:3363
function tasks.infoInput(s, inp)
  local new = inp.new or {}
  local info = s.info
  if s.page == PAGE.INFO and tryDoInfoScreenScroll(s, inp) then
    info.scrolling = true
    info.monDone = false
    info.bgLoaded = false
    info.skipCry = false
  end
  if info.scrolling then
    s.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
    s.fn = "infoWaitFade"
    se("SE_DEX_SCROLL")
    return
  end
  if new.b then
    s.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
    s.fn = "exitInfo"
    se("SE_PC_OFF")
    return
  end
  if new.a then
    local sc = s.selectedScreen
    if nativeRs() and sc == 0 then
      if info.owned then
        s.descriptionPage = 1 - (s.descriptionPage or 0)
        info.text = monInfo(s, info.dexNum, s.dexMode ~= List.DEX_MODE_HOENN, true, false)
        local m = Gfx.map("info")
        for _, i in ipairs({0x165, 0x185}) do m[i] = m[i] + s.descriptionPage end
        s.bg[3].img = Gfx.renderMap(m, "menu", bgPal(s))
        se("SE_PIN")
      end
    elseif sc == (nativeRs() and 1 or SCREEN.AREA) or sc == (nativeRs() and 2 or SCREEN.CRY) or (sc == (nativeRs() and 3 or SCREEN.SIZE) and info.owned) then
      s.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
      s.fadeExempt = { select = true }
      s.screenSwitchState = nativeRs() and sc or sc + 1
      s.fn = "switchFromInfo"
      se("SE_PIN")
    elseif sc == (nativeRs() and 3 or SCREEN.SIZE) then
      se("SE_FAILURE")
    else
      s.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
      s.fn = "exitInfo"
      se("SE_PC_OFF")
    end
    return
  end
  if (new.left or nativeRs() and new.l and RsPolicy.lr(s.session, new)) and s.selectedScreen > 0 then
    s.selectedScreen = s.selectedScreen - 1
    s.bg[1] = selectBar(s, false, s.selectedScreen)
    se("SE_DEX_PAGE")
    return
  end
  if (new.right or nativeRs() and new.r and RsPolicy.lr(s.session, new)) and s.selectedScreen < SCREEN.CANCEL then
    s.selectedScreen = s.selectedScreen + 1
    s.bg[1] = selectBar(s, false, s.selectedScreen)
    se("SE_DEX_PAGE")
  end
end

-- pokeemerald/src/pokedex.c:3458
function tasks.infoWaitFade(s)
  if not s.pal:fadeActive() then
    s.state = 0
    s.fn = "loadInfo"
  end
end

-- pokeemerald/src/pokedex.c:3467
function tasks.exitInfo(s)
  if not s.pal:fadeActive() then
    s.fadeExempt = nil
    s.info = nil
    Pokedex.lastSelected = s.selected
    Pokedex.lastRotation = s.pokeBallRotation
    s.state = 0
    s.fn = s.pageBackup == PAGE.SEARCH_RESULTS and "openSearchResults" or "openMain"
    s.monSprites = {}
  end
end

local function switchScreen(s)
  local n = s.screenSwitchState
  s.state = 0
  if n == 2 then
    s.fn = "loadCry"
  elseif n == 3 then
    s.fn = "loadSize"
  else
    s.fn = "loadArea"
  end
end

-- pokeemerald/src/pokedex.c:3437
function tasks.switchFromInfo(s)
  if not s.pal:fadeActive() then
    s.monSprites = {}
    switchScreen(s)
  end
end

local function areaContext(s)
  local C = constants(s.session)
  local RegionMap = require("src.ui.game3.rse.region_map")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = package.loaded["src.core.game3.scripting.space"]
  local store = Space and Space.store or s.session
  local encounters = assert(Mapsec.readLua("encounters.lua"), "encounters pack missing from the cache")
  local MapCatalog = require("src.import.gba.map_catalog")
  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and (Runtime._game or (Runtime.getGame and Runtime.getGame()))
  local maps = game and game.data and game.data.maps or {}
  local function mapsecOf(g, n)
    local id = MapCatalog.mapIdFor(g, n)
    local def = id and maps[id]
    return def and tonumber(def.regionMapSectionId) or RegionMap.mapsec("NONE")
  end
  local roamer
  local r = s.session and s.session.roamer
  if type(r) == "table" and (tonumber(r.species) or nativeRs()) then
    local g, n
    if r.map then
      local key = MapCatalog.slotKeyFor and MapCatalog.slotKeyFor(r.map)
      if type(key) == "string" then g, n = key:match("^(%d+):(%d+)$") end
    end
    roamer = { species = nativeRs() and Gfx.manifest().area.roamerSpecies or tonumber(r.species), active = r.active ~= false, group = tonumber(g), num = tonumber(n) }
  end
  local area = Gfx.manifest().area
  local alteringCaveId = not nativeRs() and tonumber(Flags.getVar(store, nil, C:var("VAR_ALTERING_CAVE_WILD_SET"))) or 0
  local numTables = 9
  if alteringCaveId >= numTables then alteringCaveId = 0 end
  return {
    encounters = encounters,
    groups = {
      towns = C:map("MAP_PETALBURG_CITY").group,
      dungeons = C:map("MAP_METEOR_FALLS_1F_1R").group,
      special = C:map("MAP_SAFARI_ZONE_NORTHWEST").group,
    },
    mapsecOf = mapsecOf,
    correct = function(sec)
      if nativeRs() then
        for _, pair in ipairs(RegionMap.manifest().specialPlaces) do if pair[1] == sec then return pair[2] end end
        return sec
      end
      return RegionMap.correctSpecialMapSecId({ session = s.session }, sec)
    end,
    alteringCaveMapSec = not nativeRs() and mapsecOf(C:map("MAP_ALTERING_CAVE").group, C:map("MAP_ALTERING_CAVE").num) or nil,
    alteringCaveId = alteringCaveId,
    roamer = roamer,
    flag = function(id) return Flags.getFlag(store, nil, id) == true end,
    feebas = area.feebas,
    landmarks = area.landmarks,
    hiddenSpecies = area.hiddenSpecies,
    movingMapSecs = area.movingMapSecs,
    NONE = RegionMap.mapsec("NONE"),
  }
end
Pokedex.areaContext = areaContext

local function glowImage(tilemap)
  local pal = {}
  for i = 0, 255 do pal[i] = 0 end
  if nativeRs() then
    for i = 0, tilemap.n - 1 do tilemap[i] = tilemap[i] % 4096 end
  end
  Gfx.loadPalette(pal, "areaGlow", nativeRs() and 0 or Area.GLOW_PALETTE * 16)
  return Gfx.renderMap(tilemap, "area_glow", pal, { rows = Area.SCREEN_HEIGHT })
end

-- pokeemerald/src/pokedex.c:3477
function tasks.loadArea(s)
  local st = s.state
  if st == 0 then
    if not s.pal:fadeActive() then
      s.page = PAGE.AREA
      s.selectedScreen = nativeRs() and 1 or SCREEN.AREA
      s.state = 1
    end
  elseif st == 1 then
    s.bg = { [1] = selectBar(s, true, nativeRs() and 1 or 0) }
    local RegionMap = require("src.ui.game3.rse.region_map")
    local species = Pokedex.speciesOf(item(s, s.selected).dexNum)
    local found = Area.findMapsWithMon(species, areaContext(s))
    local pal = {}
    for i = 0, 255 do pal[i] = 0 end
    Gfx.loadPalette(pal, "areaMap", 112)
    s.area = {
      found = found,
      map = nativeRs() and Kit.image(Gfx.manifest().areaMap.png) or Gfx.renderMap8(Gfx.map("area_map"), "area_map", pal),
      glow = glowImage(Area.buildGlowTilemap(found.overworld, RegionMap.mapSecAt, Gfx.manifest().area.glowMapping)),
      state = 0,
    }
    local rm = { session = s.session }
    if not nativeRs() then RegionMap.initFromPlayer(rm) end
    local cur = (package.loaded["src.core.game3.map"] or {}).currentDef
    local def = cur and cur() or {}
    local offMap = false
    for _, id in ipairs(RegionMap.manifest().offMap or {}) do
      if id == tonumber(def.regionMapSectionId) then offMap = true end
    end
    if nativeRs() then s.area.player = RsPolicy.areaRegion(RegionMap.manifest(), s.session)
    else s.area.player = not offMap and { x = rm.cursorX * 8 + 4, y = rm.cursorY * 8 + 4 + 8, blink = rm.playerIsInCave } or nil end
    s.area.markers = Area.markerPositions(found.special, Mapsec.entry)
    s.area.unknown = #found.overworld == 0 and #found.special == 0
    s.area.glowState = Area.newGlow(#found.overworld, #found.special)
    s.state = 2
  elseif st == 2 then
    if nativeRs() then s.state = 3; return end
    s.fadeExempt = { select = true }
    s.pal:beginFade(Pal.ALL, 0, 16, 0, Pal.BLACK)
    s.shown = true
    s.state = 3
  elseif st == 3 then
    if nativeRs() then s.state = 4; return end
    s.screenSwitchState = 0
    s.state = 0
    s.fn = "areaInput"
    s.area.inputState = 0
  elseif nativeRs() and st < 16 then
    s.state = st + 1
  elseif nativeRs() and st == 16 then
    s.fadeExempt = {select = true}
    s.pal:beginFade(Pal.ALL, 0, 16, 0, Pal.BLACK)
    s.state = 17
  elseif nativeRs() and st == 17 then
    s.shown, s.state = true, 18
  elseif nativeRs() and st == 18 and not s.pal:fadeActive() then
    s.screenSwitchState, s.state, s.fn, s.area.inputState = 0, 0, "areaInput", 1
  end
end

-- pokeemerald/src/pokedex_area_screen.c:656
function tasks.areaInput(s, inp)
  local new = inp.new or {}
  local a = s.area
  Area.stepGlow(a.glowState, sine)
  if a.player and a.player.blink then
    a.blinkTimer = (a.blinkTimer or 0) + 1
    if a.blinkTimer > 16 then
      a.blinkTimer = 0
      a.player.hidden = not a.player.hidden
    end
  end
  local st = a.inputState
  if st == 0 then
    if s.pal:fadeActive() then return end
    a.inputState = 1
  elseif st == 1 then
    if new.b then
      a.choice = 1
      se("SE_PC_OFF")
    elseif new.right or nativeRs() and new.r and RsPolicy.lr(s.session, new) then
      a.choice = 2
      se("SE_DEX_PAGE")
    else
      return
    end
    a.inputState = 2
  elseif st == 2 then
    s.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
    a.inputState = 3
  elseif st == 3 then
    if s.pal:fadeActive() then return end
    s.screenSwitchState = a.choice
    s.state = 0
    if a.choice == 2 then
      s.fn = "loadCry"
    else
      s.fn = "loadInfo"
    end
    s.area = nil
  end
end

local function crySpecies(s)
  return Pokedex.speciesOf(item(s, s.selected).dexNum)
end

local function cryHooks(s)
  local A = audio()
  return {
    play = function()
      A.stopCry()
      A.playCry(crySpecies(s), { noDuck = true })
      s.cry.startFrame = s.frames
    end,
    stop = function() A.stopCry() end,
    playing = function() return not A.isCryFinished() end,
    buffer = function(buf)
      local pcm = s.cry.pcm
      local t = (s.frames - (s.cry.startFrame or s.frames)) / 60
      for i = 0, 15 do
        local v = 0
        if pcm then
          local p = math.floor(t * pcm.rate + i * 2 * pcm.rate / 13379) + 1
          local b = pcm.data:byte(p)
          if b then
            if b >= 128 then b = b - 256 end
            v = tdiv(b * 120, 256)
          end
        end
        buf[i] = v % 256
      end
    end,
  }
end

local function cryPcm(species)
  local A = audio()
  local pack = A._pack
  if not pack then return nil end
  local okP, Player = pcall(require, "src.core.game3.m4a_player")
  local okS, Sample = pcall(require, "src.core.game3.m4a_sample")
  local okM, Mix = pcall(require, "src.core.game3.m4a_mix")
  if not (okP and okS and okM) then return nil end
  local slot = Player.startCry(pack, species)
  local cry = slot and slot.info and pack.index.cries[slot.info.cryIndex]
  local meta = cry and pack.samples[cry.sampleId]
  local data = meta and Sample.loadPcm(pack.samplesBin, meta)
  if not data then return nil end
  return { data = data, rate = Mix.waveRate(meta.freq) }
end

-- pokeemerald/src/pokedex.c:3534
function tasks.loadCry(s)
  local st = s.state
  if st == 0 then
    if not s.pal:fadeActive() then
      audio().pauseBgm()
      s.page = PAGE.CRY
      s.selectedScreen = nativeRs() and 2 or SCREEN.CRY
      s.state = 1
    end
  elseif st == 1 then
    s.cryBg = {}
    for _, playing in ipairs({ false, true }) do
      local pal = bgPal(s)
      -- pokeemerald/src/pokedex.c:3716
      pal[5 * 16 + 13] = playing and (18 + 28 * 32) or (15 + 21 * 32)
      s.cryBg[playing] = Gfx.renderMap(Gfx.map("cry"), "menu", pal)
    end
    s.bg = { [3] = layer("cry", s.cryBg[false], 2) }
    s.state = 2
  elseif st == 2 then
    s.bg[1] = selectBar(s, true, nativeRs() and 2 or 1)
    s.state = 3
  elseif st == 3 then
    s.state = 4
  elseif st == 4 then
    local nat = item(s, s.selected).dexNum
    local sp = Pokedex.speciesOf(nat)
    s.cryText = {
      { text = dexText("gText_CryOf"), x = nativeRs() and 80 or 82, y = nativeRs() and 32 or 33 },
      { text = sp ~= 0 and pokemon().name(sp) or "-----", x = 82, y = nativeRs() and 48 or 49 },
    }
    s.state = 5
  elseif st == 5 then
    local nat = item(s, s.selected).dexNum
    s.monSprites = { [0] = { dexNum = nat, img = monPic(s, nat), x = MON_PAGE_X, y = MON_PAGE_Y, x2 = 0, y2 = 0, prio = 0,
      affine = false, scaleY = 1 } }
    s.state = 6
  elseif st == 6 then
    if nativeRs() then
      s.cryWaveSetup = (s.cryWaveSetup or 0) + 1
      if s.cryWaveSetup < 3 then return end
      s.cryWaveSetup = nil
    end
    local bgGfx = Gfx.bytes("cry_bg")
    local tile = {}
    for y = 0, 7 do
      for x = 0, 7 do
        local b = bgGfx:byte(y * 4 + math.floor(x / 2) + 1) or 0
        tile[y * 8 + x] = (x % 2 == 0) and (b % 16) or math.floor(b / 16)
      end
    end
    s.cry = Cry.new(tile)
    s.cry.pcm = cryPcm(crySpecies(s))
    s.state = 7
  elseif st == 7 then
    if nativeRs() then
      s.cryMeterSetup = (s.cryMeterSetup or 0) + 1
      if s.cryMeterSetup < 3 then return end
      s.cryMeterSetup = nil
    end
    local man = Gfx.manifest()
    local meterPal = man.palettes.cryMeter
    local needlePal = man.palettes.cryNeedle
    local meter = nativeRs() and Gfx.map("cry_meter") or { n = 80 }
    for i = 0, 79 do meter[i] = (nativeRs() and meter[i] or i) + 9 * 4096 end
    local pal = {}
    for i = 0, 255 do pal[i] = 0 end
    for i = 0, 15 do pal[144 + i] = meterPal[i + 1] end
    s.cryMeter = Gfx.renderMap(meter, "cry_meter", pal, { width = 10, rows = 8 })
    s.cryNeedle = Gfx.sprite("cry_needle", 0, 64, 64, needlePal)
    s.state = 8
  elseif st == 8 then
    s.fadeExempt = { select = true }
    s.pal:beginFade(Pal.ALL, 0, 16, 0, Pal.BLACK)
    s.shown = true
    s.state = 9
  elseif st == 9 then
    s.state = 10
  elseif st == 10 then
    s.screenSwitchState = 0
    s.state = 0
    s.fn = "cryInput"
  end
end

-- pokeemerald/src/pokedex.c:3638
function tasks.cryInput(s, inp)
  local new = inp.new or {}
  local hooks = cryHooks(s)
  Cry.update(s.cry, hooks)
  s.cryPlaying = hooks.playing()
  if new.a then
    s.cryPlaying = true
    s.bg[3].img = s.cryBg[true]
    Cry.playButton(s.cry, hooks)
    return
  end
  s.bg[3].img = s.cryBg[s.cryPlaying and true or false]
  if s.pal:fadeActive() then return end
  local function leave(state, sound)
    s.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
    s.fadeExempt = { select = true }
    audio().resumeBgm()
    s.screenSwitchState = state
    s.fn = "switchFromCry"
    se(sound)
  end
  if new.b then return leave(1, "SE_PC_OFF") end
  if new.left or nativeRs() and new.l and RsPolicy.lr(s.session, new) then return leave(2, "SE_DEX_PAGE") end
  if new.right or nativeRs() and new.r and RsPolicy.lr(s.session, new) then
    if not item(s, s.selected).owned then
      se("SE_FAILURE")
    else
      leave(3, "SE_DEX_PAGE")
    end
  end
end

-- pokeemerald/src/pokedex.c:3694
function tasks.switchFromCry(s)
  if not s.pal:fadeActive() then
    s.cry = nil
    s.monSprites = {}
    local n = s.screenSwitchState
    s.state = 0
    if n == 2 then s.fn = "loadArea" elseif n == 3 then s.fn = "loadSize" else s.fn = "loadInfo" end
  end
end

local function trainerPic(s)
  local C = constants(s.session)
  local gender = s.session and (s.session.gender or s.session.playerGender)
  local female = gender == 1 or gender == "female" or gender == "girl"
  local id = C:id("trainer_classes", female and "TRAINER_PIC_MAY" or "TRAINER_PIC_BRENDAN")
  return Kit.rgbaImage("data/generated/gba/trainers/front/" .. tostring(id) .. ".rgba", 64, 64)
end

-- pokeemerald/src/pokedex.c:3727
function tasks.loadSize(s)
  local st = s.state
  if st == 0 then
    if not s.pal:fadeActive() then
      s.page = PAGE.SIZE
      s.selectedScreen = nativeRs() and 3 or SCREEN.SIZE
      s.state = 1
    end
  elseif st == 1 then
    s.bg = { [3] = layer("size", Gfx.renderMap(Gfx.map("size"), "menu", bgPal(s)), 2) }
    s.state = 2
  elseif st == 2 then
    s.bg[1] = selectBar(s, true, nativeRs() and 3 or 2)
    s.state = 3
  elseif st == 3 then
    local name = s.session and (s.session.name or s.session.playerName) or ""
    local label = dexText("gText_SizeComparedTo")
    local t = label:find("^の") and tostring(name) .. label or label .. tostring(name)
    local w = FrlgFont.measure(t) or 0
    s.sizeText = { text = t, x = nativeRs() and (24 + 96 - math.floor(w / 2)) or (w < 240 and math.floor((240 - w) / 2) or 0), y = nativeRs() and 120 or 121 }
    s.state = 4
  elseif st == 4 then
    s.state = 5
  elseif st == 5 then
    local e = entryFor(item(s, s.selected).dexNum)
    s.sizeTrainer = { img = trainerPic(s), x = 152, y = 56, y2 = e.trainerOffset or 0, scale = e.trainerScale or 256 }
    s.state = 6
  elseif st == 6 then
    local nat = item(s, s.selected).dexNum
    local e = entryFor(nat)
    s.sizeMon = { img = monPic(s, nat), x = 88, y = 56, y2 = e.pokemonOffset or 0, scale = e.pokemonScale or 256 }
    s.state = 7
  elseif st == 7 then
    s.fadeExempt = { select = true }
    s.pal:beginFade(Pal.ALL, 0, 16, 0, Pal.BLACK)
    s.shown = true
    s.state = 8
  elseif st == 8 then
    s.state = 9
  elseif st == 9 then
    if not s.pal:fadeActive() then
      s.screenSwitchState = 0
      s.state = 0
      s.fn = "sizeInput"
    end
  end
end

-- pokeemerald/src/pokedex.c:3825
function tasks.sizeInput(s, inp)
  local new = inp.new or {}
  if new.b then
    s.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
    s.fadeExempt = { select = true }
    s.screenSwitchState = 1
    s.fn = "switchFromSize"
    se("SE_PC_OFF")
  elseif new.left or nativeRs() and new.l and RsPolicy.lr(s.session, new) then
    s.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
    s.fadeExempt = { select = true }
    s.screenSwitchState = 2
    s.fn = "switchFromSize"
    se("SE_DEX_PAGE")
  end
end

-- pokeemerald/src/pokedex.c:3844
function tasks.switchFromSize(s)
  if not s.pal:fadeActive() then
    s.sizeMon, s.sizeTrainer = nil, nil
    s.state = 0
    s.fn = s.screenSwitchState == 2 and "loadCry" or "loadInfo"
  end
end

local cartText = cached

-- pokeemerald/src/pokedex.c:1330
local TYPE_OPTION = { "gText_DexSearchTypeNone" }
for _, t in ipairs({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17 }) do
  TYPE_OPTION[#TYPE_OPTION + 1] = RomText.key("gTypeNames", t)
end
local SEARCH_OPTION_TEXTS = {
  [SEARCH.NAME] = { titles = { "gText_DexSearchDontSpecify", "gText_DexSearchAlphaABC", "gText_DexSearchAlphaDEF",
    "gText_DexSearchAlphaGHI", "gText_DexSearchAlphaJKL", "gText_DexSearchAlphaMNO", "gText_DexSearchAlphaPQR",
    "gText_DexSearchAlphaSTU", "gText_DexSearchAlphaVWX", "gText_DexSearchAlphaYZ" } },
  [SEARCH.COLOR] = { titles = { "gText_DexSearchDontSpecify", "gText_DexSearchColorRed", "gText_DexSearchColorBlue",
    "gText_DexSearchColorYellow", "gText_DexSearchColorGreen", "gText_DexSearchColorBlack", "gText_DexSearchColorBrown",
    "gText_DexSearchColorPurple", "gText_DexSearchColorGray", "gText_DexSearchColorWhite", "gText_DexSearchColorPink" } },
  [SEARCH.TYPE_LEFT] = { titles = TYPE_OPTION },
  [SEARCH.TYPE_RIGHT] = { titles = TYPE_OPTION },
  [SEARCH.ORDER] = {
    titles = { "gText_DexSortNumericalTitle", "gText_DexSortAtoZTitle", "gText_DexSortHeaviestTitle",
      "gText_DexSortLightestTitle", "gText_DexSortTallestTitle", "gText_DexSortSmallestTitle" },
    descriptions = { "gText_DexSortNumericalDescription", "gText_DexSortAtoZDescription",
      "gText_DexSortHeaviestDescription", "gText_DexSortLightestDescription", "gText_DexSortTallestDescription",
      "gText_DexSortSmallestDescription" },
  },
  [SEARCH.MODE] = {
    titles = { "gText_DexHoennTitle", "gText_DexNatTitle" },
    descriptions = { "gText_DexHoennDescription", "gText_DexNatDescription" },
  },
}
-- pokeemerald/src/pokedex.c:1017
local TOPBAR_DESCRIPTIONS = { "gText_SearchForPkmnBasedOnParameters", "gText_SwitchPokedexListings",
  "gText_ReturnToPokedex" }
-- pokeemerald/src/pokedex.c:1042
local ITEM_DESCRIPTIONS = { "gText_ListByFirstLetter", "gText_ListByBodyColor", "gText_ListByType",
  "gText_ListByType", "gText_SelectPokedexListingMode", "gText_SelectPokedexMode", "gText_ExecuteSearchSwitch" }

local function topBarDescription(i)
  local row = Gfx.manifest().search.topBar[i + 1]
  return cartText(row.descriptionKey or TOPBAR_DESCRIPTIONS[i + 1], row.description)
end

local function itemDescription(i)
  local row = Gfx.manifest().search.items[i + 1]
  return cartText(row.descriptionKey or ITEM_DESCRIPTIONS[i + 1], row.description)
end

-- pokeemerald/src/pokedex.c:1437
local function searchOptionList(which)
  local sm = Gfx.manifest().search
  if which == SEARCH.NAME then return sm.names end
  if which == SEARCH.COLOR then return sm.colors end
  if which == SEARCH.TYPE_LEFT or which == SEARCH.TYPE_RIGHT then return sm.types end
  if which == SEARCH.ORDER then return sm.orders end
  if which == SEARCH.MODE then return sm.modes end
  return {}
end

local function searchOptionTexts(which)
  local list = searchOptionList(which)
  local keys = SEARCH_OPTION_TEXTS[which]
  if not keys then return list end
  local out = {}
  for i, t in ipairs(list) do
    out[i] = {
      title = cartText(t.titleKey or keys.titles[i], t.title),
      description = cartText(t.descriptionKey or (keys.descriptions and keys.descriptions[i]), t.description),
    }
  end
  return out
end
Pokedex.searchOptionTexts = searchOptionTexts
Pokedex.topBarDescription = topBarDescription
Pokedex.itemDescription = itemDescription

local function searchSel(q, which)
  local c = q.cursor[which] or 0
  local o = q.scroll[which] or 0
  return c + o
end

-- pokeemerald/src/pokedex.c:5491
local function searchModeSelection(q, which)
  local sm = Gfx.manifest().search
  local id = searchSel(q, which)
  if which == SEARCH.MODE then return sm.modeIds[id + 1] end
  if which == SEARCH.ORDER then return sm.orderIds[id + 1] end
  if which == SEARCH.NAME then return id == 0 and 0xFF or id end
  if which == SEARCH.COLOR then return id == 0 and 0xFF or id - 1 end
  if which == SEARCH.TYPE_LEFT or which == SEARCH.TYPE_RIGHT then return sm.typeIds[id + 1] end
  return 0
end
Pokedex.searchModeSelection = searchModeSelection

-- pokeemerald/src/pokedex.c:5327
local function searchHighlights(s, q)
  local sm = Gfx.manifest().search
  local m = Gfx.map(s.nationalEnabled and "search_national" or "search_hoenn")
  if nativeRs() and not s.nationalEnabled then
    for i = 0, 16 do
      m[0x140 + i], m[0x160 + i] = m[0x180 + i], m[0x1A0 + i]
      m[0x180 + i], m[0x1A0 + i] = 1, 1
    end
  end
  local function rect(flags, x, y, w)
    for i = 0, w - 1 do
      for dy = 0, 1 do
        local k = (y + dy) * 32 + x + i
        m[k] = m[k] % 4096 + flags * 4096
      end
    end
  end
  local function hl(which, unselected, disabled)
    local flags = (unselected and 1 or 0) + (disabled and 2 or 0)
    if which <= 2 then
      local t = sm.topBar[which + 1]
      rect(flags, t.x, t.y, t.width)
      return
    end
    if which == 10 then
      local it = sm.items[SEARCH.TYPE_LEFT + 1]
      rect(flags, it.titleX, it.titleY, it.titleWidth)
      return
    end
    local item0 = which - 3
    local it = sm.items[item0 + 1]
    if item0 == SEARCH.NAME or item0 == SEARCH.COLOR or item0 == SEARCH.ORDER or item0 == SEARCH.MODE then
      rect(flags, it.titleX, it.titleY, it.titleWidth)
      rect(flags, it.selX, it.selY, it.selWidth)
    elseif item0 == SEARCH.TYPE_LEFT or item0 == SEARCH.TYPE_RIGHT then
      rect(flags, it.selX, it.selY, it.selWidth)
    elseif item0 == SEARCH.OK then
      rect(flags, it.titleX, s.nationalEnabled and it.titleY or (it.titleY - 2), it.titleWidth)
    end
  end
  local top = q.topBar
  local disabledRows = top ~= TOPBAR.SEARCH
  hl(0, top ~= TOPBAR.SEARCH, false)
  hl(1, top ~= TOPBAR.SHIFT, false)
  hl(2, top ~= TOPBAR.CANCEL, false)
  hl(3 + SEARCH.NAME, true, disabledRows)
  hl(3 + SEARCH.COLOR, true, disabledRows)
  hl(10, true, disabledRows)
  hl(3 + SEARCH.TYPE_LEFT, true, disabledRows)
  hl(3 + SEARCH.TYPE_RIGHT, true, disabledRows)
  hl(3 + SEARCH.ORDER, true, top == TOPBAR.CANCEL)
  hl(3 + SEARCH.MODE, true, top == TOPBAR.CANCEL)
  hl(3 + SEARCH.OK, true, top == TOPBAR.CANCEL)
  if q.phase ~= "topbar" then
    local mi = q.menuItem
    if mi == SEARCH.TYPE_LEFT or mi == SEARCH.TYPE_RIGHT then hl(10, false, false) end
    hl(3 + mi, false, false)
  end
  if q.paramBox then
    -- pokeemerald/src/pokedex.c:5440
    m[0x11] = 0xC0B
    local right = nativeRs() and 0x1C or 0x1E
    for i = 0x12, right do m[i] = 0x80D end
    for j = 1, 12 do
      m[0x11 + j * 32] = 0x40A
      for i = 0x12, right do m[j * 32 + i] = 2 end
    end
    m[0x1B1] = 0x40B
    for i = 0x12, right do m[0x1A0 + i] = 0xD end
    if nativeRs() then
      m[0x1D] = 0x80B
      for j = 1, 12 do m[j * 32 + 0x1D] = 0xA end
      m[0x1BD] = 0xB
    end
  end
  local pal = {}
  for i = 0, 255 do pal[i] = 0 end
  Gfx.loadPalette(pal, "searchMenu", 1, 1, 63)
  s.bg = { [3] = layer("search", Gfx.renderMap(m, "search", pal), 3) }
end

local function searchText(s, q)
  local out = {}
  local function add(text, x, y) out[#out + 1] = { text = text, x = x, y = nativeRs() and y - 1 or y } end
  local function title(which, x, y)
    local texts = searchOptionTexts(which)
    local t = texts[searchSel(q, which) + 1]
    if t then add(t.title, x, y) end
  end
  if q.phase ~= "param" then
    title(SEARCH.NAME, 0x2D, 0x11)
    title(SEARCH.COLOR, 0x2D, 0x21)
    title(SEARCH.TYPE_LEFT, 0x2D, 0x31)
    title(SEARCH.TYPE_RIGHT, 0x5D, 0x31)
    title(SEARCH.ORDER, 0x2D, 0x41)
    if s.nationalEnabled then title(SEARCH.MODE, 0x2D, 0x51) end
  else
    title(SEARCH.NAME, 0x2D, 0x11)
    title(SEARCH.COLOR, 0x2D, 0x21)
    title(SEARCH.TYPE_LEFT, 0x2D, 0x31)
    title(SEARCH.TYPE_RIGHT, 0x5D, 0x31)
    title(SEARCH.ORDER, 0x2D, 0x41)
    if s.nationalEnabled then title(SEARCH.MODE, 0x2D, 0x51) end
    local texts = searchOptionTexts(q.menuItem)
    local off = q.scroll[q.menuItem] or 0
    for i = 0, 5 do
      local t = texts[off + i + 1]
      if not t then break end
      add(t.title, 152, i * 16 + 9)
    end
    add(dexText("gText_SelectorArrow"), 144, (q.cursor[q.menuItem] or 0) * 16 + 9)
  end
  add(q.message or "", nativeRs() and 9 or 8, 121)
  s.searchText = out
end

local function refreshSearch(s)
  local q = s.searchState
  searchHighlights(s, q)
  searchText(s, q)
end

local function setSearchMessage(q, text)
  q.message = text
end

-- pokeemerald/src/pokedex.c:5521
local function setDefaultSearchModeAndOrder(s, q)
  q.cursor[SEARCH.MODE] = s.dexModeBackup == List.DEX_MODE_NATIONAL and 1 or 0
  q.cursor[SEARCH.ORDER] = s.dexOrderBackup
end

-- pokeemerald/src/pokedex.c:4832
function tasks.loadSearch(s)
  local st = s.state
  if st == 0 then
    if not s.pal:fadeActive() then
      s.page = PAGE.SEARCH
      s.monSprites = {}
      s.sprites = {}
      local q = { topBar = TOPBAR.SEARCH, menuItem = SEARCH.NAME, cursor = {}, scroll = {}, phase = "topbar" }
      for i = 0, 6 do q.cursor[i], q.scroll[i] = 0, 0 end
      s.searchState = q
      s.state = 1
    end
  elseif st == 1 then
    local q = s.searchState
    setDefaultSearchModeAndOrder(s, q)
    setSearchMessage(q, topBarDescription(TOPBAR.SEARCH))
    s.searchArrows = {
      { x = 184, y = 4, down = false, data2 = 0, invisible = true },
      { x = 184, y = 108, down = true, data2 = 0, invisible = true },
    }
    refreshSearch(s)
    s.state = 2
  elseif st == 2 then
    s.pal:beginFade(Pal.ALL, 0, 16, 0, Pal.BLACK)
    s.state = 3
  elseif st == 3 then
    s.shown = true
    s.state = 4
  elseif st == 4 then
    if not s.pal:fadeActive() then
      s.state = 0
      s.fn = "searchTopBar"
      s.searchState.phase = "topbar"
      setSearchMessage(s.searchState, topBarDescription(s.searchState.topBar))
      refreshSearch(s)
    end
  end
end

-- pokeemerald/src/pokedex.c:4931
function tasks.searchTopBar(s, inp)
  local new = inp.new or {}
  local q = s.searchState
  if new.b then
    se("SE_PC_OFF")
    s.fn = "exitSearch"
    return
  end
  if new.a then
    if q.topBar == TOPBAR.SEARCH then
      se("SE_PIN")
      q.menuItem = SEARCH.NAME
      s.fn = "searchMenu"
    elseif q.topBar == TOPBAR.SHIFT then
      se("SE_PIN")
      q.menuItem = SEARCH.ORDER
      s.fn = "searchMenu"
    else
      se("SE_PC_OFF")
      s.fn = "exitSearch"
      return
    end
    q.phase = "menu"
    setSearchMessage(q, itemDescription(q.menuItem))
    refreshSearch(s)
    return
  end
  if new.left and q.topBar > TOPBAR.SEARCH then
    se("SE_DEX_PAGE")
    q.topBar = q.topBar - 1
    setSearchMessage(q, topBarDescription(q.topBar))
    refreshSearch(s)
  end
  if new.right and q.topBar < TOPBAR.CANCEL then
    se("SE_DEX_PAGE")
    q.topBar = q.topBar + 1
    setSearchMessage(q, topBarDescription(q.topBar))
    refreshSearch(s)
  end
end

-- pokeemerald/src/pokedex.c:4988
function tasks.searchMenu(s, inp)
  local new = inp.new or {}
  local q = s.searchState
  local sm = Gfx.manifest().search
  local key
  if q.topBar ~= TOPBAR.SEARCH then
    key = s.nationalEnabled and "ShiftNatDex" or "ShiftHoennDex"
  else
    key = s.nationalEnabled and "SearchNatDex" or "SearchHoennDex"
  end
  local map = sm.movement[key]
  if new.b then
    se("SE_BALL")
    setDefaultSearchModeAndOrder(s, q)
    q.phase = "topbar"
    s.fn = "searchTopBar"
    setSearchMessage(q, topBarDescription(q.topBar))
    refreshSearch(s)
    return
  end
  if new.a then
    if q.menuItem == SEARCH.OK then
      if q.topBar ~= TOPBAR.SEARCH then
        Pokedex.lastRotation = POKEBALL_ROTATION_TOP
        s.pokeBallRotationBackup = POKEBALL_ROTATION_TOP
        Pokedex.lastSelected = 0
        s.selectedBackup = 0
        s.session.pokedex = type(s.session.pokedex) == "table" and s.session.pokedex or {}
        local mode = searchModeSelection(q, SEARCH.MODE)
        if not s.nationalEnabled then mode = List.DEX_MODE_HOENN end
        s.session.pokedex.mode = mode
        s.dexModeBackup = mode
        s.session.pokedex.order = searchModeSelection(q, SEARCH.ORDER)
        s.dexOrderBackup = s.session.pokedex.order
        se("SE_PC_OFF")
        s.fn = "exitSearch"
      else
        setSearchMessage(q, dexText("gText_SearchingPleaseWait"))
        refreshSearch(s)
        s.fn = "startSearch"
        se("SE_DEX_SEARCH")
        q.searchFrames = 0
      end
    else
      se("SE_PIN")
      q.paramBox = true
      q.phase = "param"
      q.savedCursor = q.cursor[q.menuItem]
      q.savedScroll = q.scroll[q.menuItem]
      local texts = searchOptionTexts(q.menuItem)
      local t = texts[searchSel(q, q.menuItem) + 1]
      setSearchMessage(q, t and t.description or "")
      refreshSearch(s)
      s.fn = "searchParam"
    end
    return
  end
  local function move(col, sound)
    local nxt = map[q.menuItem + 1][col]
    if nxt ~= 0xFF then
      se(sound)
      q.menuItem = nxt
      setSearchMessage(q, itemDescription(q.menuItem))
      refreshSearch(s)
    end
  end
  if new.left then move(1, "SE_SELECT") end
  if new.right then move(2, "SE_SELECT") end
  if new.up then move(3, "SE_SELECT") end
  if new.down then move(4, "SE_SELECT") end
end

-- pokeemerald/src/pokedex.c:5083
function tasks.startSearch(s)
  local q = s.searchState
  local ctx = s.ctx
  local mode = searchModeSelection(q, SEARCH.MODE)
  local order = searchModeSelection(q, SEARCH.ORDER)
  s.list = List.search(ctx, mode, order, searchModeSelection(q, SEARCH.NAME), searchModeSelection(q, SEARCH.COLOR),
    searchModeSelection(q, SEARCH.TYPE_LEFT), searchModeSelection(q, SEARCH.TYPE_RIGHT), letterRanges())
  s.fn = "waitSearch"
end

-- pokeemerald/src/pokedex.c:5096
function tasks.waitSearch(s)
  local q = s.searchState
  q.searchFrames = (q.searchFrames or 0) + 1
  if q.searchFrames < 60 then return end
  if s.list.count ~= 0 then
    se("SE_SUCCESS")
    setSearchMessage(q, dexText("gText_SearchCompleted"))
  else
    se("SE_FAILURE")
    setSearchMessage(q, dexText("gText_NoMatchingPkmnWereFound"))
  end
  refreshSearch(s)
  s.fn = "searchDone"
end

-- pokeemerald/src/pokedex.c:5115
function tasks.searchDone(s, inp)
  local new = inp.new or {}
  local q = s.searchState
  if new.a then
    if s.list.count ~= 0 then
      s.screenSwitchState = 1
      s.dexMode = searchModeSelection(q, SEARCH.MODE)
      s.dexOrder = searchModeSelection(q, SEARCH.ORDER)
      s.fn = "exitSearch"
      se("SE_PC_OFF")
    else
      s.fn = "searchMenu"
      q.phase = "menu"
      setSearchMessage(q, itemDescription(q.menuItem))
      refreshSearch(s)
      se("SE_BALL")
    end
  end
end

-- pokeemerald/src/pokedex.c:5156
function tasks.searchParam(s, inp)
  local new, rep = inp.new or {}, inp.rep or {}
  local q = s.searchState
  local mi = q.menuItem
  local maxOption = #searchOptionList(mi) - 1
  if new.a or new.b then
    se(new.a and "SE_PIN" or "SE_BALL")
    if new.b then
      q.cursor[mi] = q.savedCursor
      q.scroll[mi] = q.savedScroll
    end
    q.paramBox = false
    q.phase = "menu"
    setSearchMessage(q, itemDescription(mi))
    refreshSearch(s)
    s.fn = "searchMenu"
    return
  end
  local moved = false
  if rep.up then
    if q.cursor[mi] ~= 0 then
      q.cursor[mi] = q.cursor[mi] - 1
      moved = true
    elseif q.scroll[mi] ~= 0 then
      q.scroll[mi] = q.scroll[mi] - 1
      moved = true
    end
  elseif rep.down then
    if q.cursor[mi] < 5 and q.cursor[mi] < maxOption then
      q.cursor[mi] = q.cursor[mi] + 1
      moved = true
    elseif maxOption > 5 and q.scroll[mi] < maxOption - 5 then
      q.scroll[mi] = q.scroll[mi] + 1
      moved = true
    end
  end
  if moved then
    se("SE_SELECT")
    local t = searchOptionTexts(mi)[searchSel(q, mi) + 1]
    setSearchMessage(q, t and t.description or "")
    refreshSearch(s)
  end
end

-- pokeemerald/src/pokedex.c:5247
function tasks.exitSearch(s)
  s.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
  s.fn = "exitSearchWait"
end

-- pokeemerald/src/pokedex.c:1817
function tasks.exitSearchWait(s)
  if s.pal:fadeActive() then return end
  s.searchState = nil
  s.searchText = nil
  s.monSprites = {}
  s.state = 0
  if s.screenSwitchState ~= 0 then
    s.selected = 0
    s.pokeBallRotation = POKEBALL_ROTATION_TOP
    s.fn = "openSearchResults"
  else
    s.pokeBallRotation = s.pokeBallRotationBackup
    s.selected = s.selectedBackup
    s.dexMode = s.nationalEnabled and s.dexModeBackup or List.DEX_MODE_HOENN
    s.dexOrder = s.dexOrderBackup
    local pd = type(s.session.pokedex) == "table" and s.session.pokedex or nil
    if pd and pd.mode ~= nil then
      s.dexMode = s.nationalEnabled and pd.mode or List.DEX_MODE_HOENN
      s.dexOrder = pd.order or s.dexOrder
    end
    s.fn = "openMain"
  end
end

-- pokeruby/src/pokedex.c:3900, pokeemerald/src/pokedex.c:4039
function Pokedex.caughtFlashOn(timer)
  return math.floor(timer / 16) % 2 == 1
end

-- pokeruby/src/pokedex.c:3816
function Pokedex.caughtPalettes(pal, palettes, rs)
  if rs then
    for i = 0, 239 do pal[i] = 0 end
    for i = 1, 79 do pal[32 + i] = palettes.hoenn[i + 1] end
  end
  local slot = rs and 80 or 48
  local on, off = {}, {}
  for i = 0, 255 do on[i], off[i] = pal[i], pal[i] end
  for i = 1, 7 do
    -- pokeruby/src/pokedex.c:3902, pokeemerald/src/pokedex.c:4041
    on[slot + i] = palettes.hoenn[i + 1]
    -- pokeruby/src/pokedex.c:3904, pokeemerald/src/pokedex.c:4045
    off[slot + i] = rs and palettes.registrationFlash[i + 1] or palettes.hoenn[49 + i]
  end
  return pal, on, off
end

-- pokeemerald/src/pokedex.c:3957
function tasks.caught(s)
  local st = s.state
  local c = s.caught
  if st == 0 then
    if not s.pal:fadeActive() then
      s.page = PAGE.CAUGHT
      s.state = 1
    end
  elseif st == 1 then
    local map = Gfx.map("info")
    if nativeRs() then
      for i = 0, math.min(639, map.n - 1) do map[i] = (map[i] + 0x2000) % 65536 end
      s.descriptionPage = 0
    end
    local pal, on, off = Pokedex.caughtPalettes(Gfx.bgPalette("hoenn"), Gfx.manifest().palettes, nativeRs())
    c.basePal = pal
    c.map = map
    s.bg = { [3] = layer("info", Gfx.renderMap(map, "menu", pal), 3) }
    c.onPal, c.offPal = on, off
    c.onImg, c.offImg = Gfx.renderMap(map, "menu", on), Gfx.renderMap(map, "menu", off)
    c.footprint = footprintImage(c.dexNum)
    s.state = 2
  elseif st == 2 then
    s.state = 3
  elseif st == 3 then
    c.text = monInfo(s, c.dexNum, s.nationalEnabled, true, true)
    s.state = 4
  elseif st == 4 then
    local img = pokemon().frontPic(pokemon().picSpecies(Pokedex.speciesOf(c.dexNum), c.personality or 0), nil, false,
      c.personality or 0, "dex")
    c.mon = { dexNum = c.dexNum, img = img and img.image, x = MON_PAGE_X, y = MON_PAGE_Y, x2 = 0, y2 = 0, prio = 0,
      affine = false, scaleY = 1 }
    s.monSprites = { [0] = c.mon }
    s.pal:beginFade(Pal.ALL, 0, 16, 0, Pal.BLACK)
    s.state = 5
  elseif st == 5 then
    s.shown = true
    s.state = 6
  elseif st == 6 then
    if not s.pal:fadeActive() then
      audio().playCry(Pokedex.speciesOf(c.dexNum))
      c.palTimer = 0
      s.fn = "caughtInput"
    end
  end
end

-- pokeemerald/src/pokedex.c:4030
function tasks.caughtInput(s, inp)
  local new = inp.new or {}
  local c = s.caught
  local flipped = nativeRs() and not new.b and new.a and (s.descriptionPage or 0) == 0
  if flipped then
    s.descriptionPage = 1
    c.text = monInfo(s, c.dexNum, s.nationalEnabled, true, true)
    for _, i in ipairs({0x165, 0x185}) do c.map[i] = c.map[i] + 1 end
    c.onImg, c.offImg = Gfx.renderMap(c.map, "menu", c.onPal), Gfx.renderMap(c.map, "menu", c.offPal)
    s.bg[3].img = Gfx.renderMap(c.map, "menu", c.basePal)
    se("SE_PIN")
  end
  if (new.a and not flipped) or new.b then
    s.pal:beginFade(Pal.BG, 0, 0, 16, Pal.BLACK)
    s.fadeExempt = { mon = true }
    c.mon.cb = "slideToCenter"
    s.fn = "caughtExit"
    return
  end
  c.palTimer = c.palTimer + 1
  c.flash = Pokedex.caughtFlashOn(c.palTimer)
end

-- pokeemerald/src/pokedex.c:4049
function tasks.caughtExit(s)
  if not s.pal:fadeActive() then
    local c = s.caught
    local Stack = require("src.ui.game3.stack")
    -- pokeemerald/src/pokedex.c:4069
    local species = Pokedex.speciesOf(c.dexNum)
    local pic = pokemon().frontPic(pokemon().picSpecies(species, c.personality or 0), nil, c.shiny,
      c.personality or 0, "dex")
    c.mon.img = assert(pic and pic.image, "caught mon palette missing from the cache")
    Pokedex.Host._s = nil
    Stack.pop(Pokedex.ID)
    if c.onDone then c.onDone({ sprite = c.mon, species = species, personality = c.personality,
      otId = c.otId, otSecretId = c.otSecretId, shiny = c.shiny }) end
  end
end

function Pokedex.frame(s, inp)
  s.frames = s.frames + 1
  local fn = tasks[s.fn]
  if fn then fn(s, inp) end
  if Pokedex.Host._s ~= s and not s.detached then return end
  animateSprites(s)
  if s.cry then
    s.cryNeedleX, s.cryNeedleY = Cry.stepNeedle(s.cry, sine)
  end
  if s.searchArrows and s.fn == "searchParam" then
    local q = s.searchState
    local last = #searchOptionList(q.menuItem) - 1
    for _, a in ipairs(s.searchArrows) do
      local off = q.scroll[q.menuItem] or 0
      if a.down then
        a.invisible = not (last > 5 and off < last - 5)
      else
        a.invisible = not (last > 5 and off ~= 0)
      end
      a.y2 = tdiv(sine(u8(a.data2 + (a.down and 128 or 0))), 128)
      a.data2 = u8(a.data2 + 8)
    end
  elseif s.searchArrows then
    for _, a in ipairs(s.searchArrows) do a.invisible = true end
  end
  s.pal:updateFade()
  if s.fadeExempt and not s.pal:fadeActive() and Kit.fadeY(s.pal, 0) == 0 then s.fadeExempt = nil end
end

-- pokeemerald/include/gba/io_reg.h:540
local function drawLayer(l, oy)
  if not (l and l.img and l.visible) then return end
  local vofs = (l.vofs or 0) % 256
  local hofs = (l.hofs or 0) % 256
  for _, dy in ipairs({ 0, 256 }) do
    for _, dx in ipairs({ 0, 256 }) do
      love.graphics.draw(l.img, dx - hofs, (oy or 0) + dy - vofs)
    end
  end
end

local function drawSprite(spr)
  if spr.invisible then return end
  local img = interfaceSprite(spr.tile, spr.w, spr.h)
  local x = spr.x + (spr.x2 or 0) - spr.w / 2
  local y = spr.y + (spr.y2 or 0) - spr.h / 2
  if spr.vflip then
    love.graphics.draw(img, x, y + spr.h, 0, 1, -1)
  else
    love.graphics.draw(img, x, y)
  end
end

local function drawMon(spr, silhouette)
  if not spr or spr.invisible or not spr.img then return end
  local sy = spr.scaleY or 1
  if sy <= 0 then return end
  local cx = spr.x + (spr.x2 or 0)
  local cy = spr.y + (spr.y2 or 0)
  love.graphics.draw(spr.img, cx, cy, 0, 1, sy, 32, 32)
end

local function drawText(t, colors, opts)
  for _, e in ipairs(t or {}) do
    FrlgFont.draw(e.text, e.x, e.y, { colors = colors, font = opts and opts.font, maxWidth = 240 })
  end
end

local function sprites(s, prio)
  for i = #s.sprites, 1, -1 do
    local spr = s.sprites[i]
    if spr.prio == prio and not spr.objwin then drawSprite(spr) end
  end
end

local ballShader
local maskCanvas

local function alphaShader()
  ballShader = ballShader or love.graphics.newShader([[
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      vec4 p = Texel(tex, tc);
      if (p.a < 0.5) discard;
      return p * color;
    }
  ]])
  return ballShader
end

local maskShader

local function tintMask(img, color, x, y)
  maskShader = maskShader or love.graphics.newShader([[
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      vec4 p = Texel(tex, tc);
      return vec4(color.rgb, p.a * color.a);
    }
  ]])
  love.graphics.setShader(maskShader)
  love.graphics.setColor(color)
  love.graphics.draw(img, x, y)
  love.graphics.setShader()
  love.graphics.setColor(1, 1, 1, 1)
end

local function stencilled(maskFn, test, value, drawFn)
  maskCanvas = maskCanvas or PixelCanvas.new(240, 160)
  maskCanvas:setFilter("nearest", "nearest")
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setCanvas({ maskCanvas, stencil = true })
  love.graphics.clear(0, 0, 0, 0, 0)
  love.graphics.stencil(maskFn, "replace", 1)
  love.graphics.setStencilTest(test, value)
  drawFn()
  love.graphics.setStencilTest()
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(maskCanvas, 0, 0)
end

local function ballStencil(s)
  local img = interfaceSprite(16, 32, 32)
  love.graphics.setShader(alphaShader())
  for _, spr in ipairs(s.sprites) do
    if spr.objwin then
      local r = (spr.rot or 0) * 2 * math.pi / 256
      love.graphics.draw(img, spr.x + (spr.x2 or 0), spr.y + (spr.y2 or 0), r, 1, 1, 16, 16)
    end
  end
  love.graphics.setShader()
end

local function listRowsText(s)
  local colors = textColors(s, 15, 3)
  local vofs = s.bg2vofs or 0
  local pal = bgPalRead(s)
  local ball = Gfx.sprite("caught_ball", 0, 8, 16, { pal[0], pal[1], pal[2], pal[3], pal[4], pal[5], pal[6], pal[7], pal[8],
    pal[9], pal[10], pal[11], pal[12], pal[13], pal[14], pal[15] })
  -- pokeemerald/src/pokedex.c:847
  local numPrefix = "№"
  for r, row in pairs(s.rows) do
    local y = (r * 8 - vofs) % 256
    if y > 160 then y = y - 256 end
    if y > -16 and y < 160 then
      if row.owned then love.graphics.draw(ball, 136, y) end
      if nativeRs() then
        local number = Gfx.sprite("number", 0, 8, 16, spritePal())
        love.graphics.draw(number, 144, y)
        FrlgFont.draw(row.num, 152, y, {colors = colors, font = "normal"})
        FrlgFont.draw(row.name, 172, y, {colors = colors, font = "normal"})
      else
        FrlgFont.draw(numPrefix .. row.num, 144, y + 1, { colors = colors, font = "narrow" })
        FrlgFont.draw(row.name, 176, y + 1, { colors = colors, font = "narrow" })
      end
    end
  end
end

local function drawList(s)
  drawLayer(s.bg[3])
  for i = MAX_MONS_ON_SCREEN - 1, 0, -1 do
    local spr = s.monSprites[i]
    if spr and spr.prio == 3 and not (s.fadeExempt and s.fadeExempt.mon and spr == s.movingMon) then drawMon(spr) end
  end
  listRowsText(s)
  sprites(s, 2)
  stencilled(function() ballStencil(s) end, "equal", 0, function() drawLayer(s.bg[1]) end)
  sprites(s, 1)
  local menu = s.bg[0]
  if menu then
    menu.vofs = s.menuY
    drawLayer(menu)
  end
  sprites(s, 0)
end

local function drawInfo(s)
  local info = s.info or {}
  drawLayer(s.bg[3])
  local colors = textColors(s, 15, 3)
  drawText(info.text, colors)
  if info.footprint then
    -- pokeemerald/src/pokedex.c:4583
    tintMask(info.footprint, Gfx.color(Gfx.manifest().palettes.messageBox[nativeRs() and 2 or 3]), 25 * 8, 8 * 8)
  end
end

local function drawArea(s)
  local a = s.area
  if not a then return end
  if nativeRs() then love.graphics.draw(a.map, 0, 0) else drawLayer(layer("area_map", a.map, 3, 0, -8)) end
  local g = a.glowState
  if a.glow and g then
    love.graphics.setShader(alphaShader())
    love.graphics.setColor(0, 0, 0, 1 - math.min(16, g.evb) / 16)
    love.graphics.draw(a.glow, 0, 8)
    love.graphics.setShader()
    love.graphics.setBlendMode("add")
    local k = math.min(16, g.eva) / 16
    love.graphics.setColor(k, k, k, 1)
    love.graphics.draw(a.glow, 0, 8)
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
  end
  local RegionMap = require("src.ui.game3.rse.region_map")
  local man = RegionMap.manifest()
  if a.player and not a.player.hidden then
    local gender = s.session and (s.session.gender or s.session.playerGender)
    local female = gender == 1 or gender == "female" or gender == "girl"
    local img = Kit.image((female and man.sprites.may or man.sprites.brendan).png)
    if img then love.graphics.draw(img, a.player.x - 8, a.player.y - 8) end
  end
  if g and not g.markersInvisible then
    local pal = Gfx.manifest().palettes.areaMarker
    local img = Gfx.sprite("area_marker", 0, 16, 16, pal)
    for _, m in ipairs(a.markers) do love.graphics.draw(img, m.x - 8, m.y - 8) end
  end
  if a.unknown then
    local pal = Gfx.manifest().palettes.areaUnknown
    for i = 0, 2 do
      local img = Gfx.sprite("area_unknown", i * 16, 32, 32, pal)
      love.graphics.draw(img, i * 32 + 160 - 16, 140 - 16)
    end
  end
end

local function cryWaveImage(s)
  local c = s.cry
  if not c then return nil end
  if c.dirty or not s.cryWaveImg then
    local pal = Gfx.manifest().palettes.cryBg
    local data = s.cryWaveData or love.image.newImageData(256, 56)
    s.cryWaveData = data
    for y = 0, 55 do
      for x = 0, 255 do
        local v = c.pixels[y * 256 + x] or 0
        if v == 0 then
          data:setPixel(x, y, 0, 0, 0, 0)
        else
          local r, g, b = Gfx.rgb8(pal[v + 1])
          data:setPixel(x, y, r, g, b, 1)
        end
      end
    end
    if s.cryWaveImg then s.cryWaveImg:replacePixels(data) else
      s.cryWaveImg = love.graphics.newImage(data)
      s.cryWaveImg:setFilter("nearest", "nearest")
    end
    c.dirty = false
  end
  return s.cryWaveImg
end

local function drawCry(s)
  drawLayer(s.bg[3])
  local wave = cryWaveImage(s)
  if wave then drawLayer(layer("wave", wave, 3, s.cry.playhead, 0), 96) end
  local colors = textColors(s, 15, 3)
  drawText(s.cryText, colors)
  if s.cryMeter then love.graphics.draw(s.cryMeter, 18 * 8, 3 * 8) end
end

local function drawSize(s)
  drawLayer(s.bg[3])
  drawText({ s.sizeText }, textColors(s, 15, 3))
  love.graphics.setColor(0, 0, 0, 1)
  for _, t in ipairs({ s.sizeTrainer, s.sizeMon }) do
    if t and t.img then
      local k = 256 / math.max(1, t.scale)
      love.graphics.draw(t.img, t.x, t.y + t.y2, 0, k, k, 32, 32)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function drawSearch(s)
  drawLayer(s.bg[3])
  local pal = Gfx.manifest().palettes.searchMenu
  local colors = nativeRs() and textColors(s)
    or { fg = Gfx.color(pal[16]), shadow = Gfx.color(pal[3]), bg = { 0, 0, 0, 0 } }
  drawText(s.searchText, colors)
  for _, a in ipairs(s.searchArrows or {}) do
    if not a.invisible then
      local img = interfaceSprite(1, 16, 8)
      local x, y = a.x - 8, a.y + (a.y2 or 0) - 4
      if a.down then love.graphics.draw(img, x, y + 8, 0, 1, -1) else love.graphics.draw(img, x, y) end
    end
  end
end

local function drawCaught(s)
  local c = s.caught
  if not c then return end
  local l = s.bg[3]
  if l then
    if c.palTimer and c.palTimer > 0 then l.img = c.flash and c.onImg or c.offImg end
    drawLayer(l)
  end
  drawText(c.text, nativeRs() and textColors(s) or { fg = Gfx.color(c.basePal[15]), shadow = Gfx.color(c.basePal[3]), bg = { 0, 0, 0, 0 } })
  if c.footprint then
    tintMask(c.footprint, Gfx.color(Gfx.manifest().palettes.messageBox[nativeRs() and 2 or 3]), 25 * 8, 8 * 8)
  end
end

function Pokedex.draw(s)
  if not s then return end
  love.graphics.push("all")
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 240, 160)
  love.graphics.setColor(1, 1, 1, 1)
  if s.shown then
    local page = s.page
    if page == PAGE.MAIN or page == PAGE.SEARCH_RESULTS then
      drawList(s)
    elseif page == PAGE.INFO then
      drawInfo(s)
    elseif page == PAGE.AREA then
      drawArea(s)
    elseif page == PAGE.CRY then
      drawCry(s)
    elseif page == PAGE.SIZE then
      drawSize(s)
    elseif page == PAGE.SEARCH then
      drawSearch(s)
    elseif page == PAGE.CAUGHT then
      drawCaught(s)
    end
    local ex = s.fadeExempt or {}
    if not ex.select and s.bg[1] and s.bg[1].key == "select" then drawLayer(s.bg[1]) end
    if page ~= PAGE.MAIN and page ~= PAGE.SEARCH_RESULTS then
      for i = MAX_MONS_ON_SCREEN - 1, 0, -1 do
        local spr = s.monSprites[i]
        if spr and not ex.mon then drawMon(spr) end
      end
      if page == PAGE.CRY and s.cryNeedle and not ex.select then
        love.graphics.draw(s.cryNeedle, 184 + (s.cryNeedleX or 0), 80 + (s.cryNeedleY or 0),
          -(s.cry and s.cry.needle.rotation or 0) * 2 * math.pi / 256, 1, 1, 32, 32)
      end
    end
  end
  Kit.drawFade(s.pal, 0)
  local ex = s.fadeExempt or {}
  if s.shown then
    if ex.select and s.bg[1] and s.bg[1].key == "select" then drawLayer(s.bg[1]) end
    if ex.mon then
      for i = MAX_MONS_ON_SCREEN - 1, 0, -1 do
        local spr = s.monSprites[i]
        if spr and (s.page ~= PAGE.MAIN and s.page ~= PAGE.SEARCH_RESULTS or spr == s.movingMon) then drawMon(spr) end
      end
    end
  end
  love.graphics.pop()
end

local Host = { isMenu = true }
Pokedex.Host = Host
Host._s = nil
Host._step = nil

local function push(s)
  local Stack = require("src.ui.game3.stack")
  Host._s = s
  Host._step = Kit.stepper()
  Stack.push(Pokedex.ID, Host, { hideBelow = true, fullscreen = true })
  return s
end

-- pokeemerald/src/pokedex.c:1591
function Pokedex.show(dex, opts)
  opts = opts or {}
  opts.dex = dex or opts.dex
  local s = newView(opts)
  return push(s)
end

-- pokeemerald/src/pokedex.c:3944
function Pokedex.showCaughtMon(species, opts)
  opts = opts or {}
  local s = newView(opts)
  local nat = pokemon().national(species) or species
  s.caught = { dexNum = nat, personality = opts.personality, otId = opts.otId, otSecretId = opts.otSecretId,
    shiny = opts.shiny, onDone = opts.onDone }
  s.fn = "caught"
  s.state = 0
  return push(s)
end

function Pokedex.active()
  return Host._s
end

function Pokedex.reset()
  if Host._s then
    Host._s = nil
    require("src.ui.game3.stack").pop(Pokedex.ID)
  end
  Host._step = nil
  entriesPack, regionalPack = nil, nil
  Gfx.reset()
  Gfx.resetSprites()
end

function Host.handleInput(input)
  if Host._step then Host._step:collect(input) end
end

function Host.update(dt)
  local s = Host._s
  if not (s and Host._step) then return end
  Host._step:run(dt, function(inp)
    if Host._s ~= s then return true end
    Pokedex.frame(s, inp)
    if Host._s ~= s then return true end
    return nil
  end)
end

function Host.draw()
  Pokedex.draw(Host._s)
end

Pokedex.tasks = tasks

return Pokedex
