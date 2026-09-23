-- pokefirered/src/fame_checker.c:625 UseFameChecker

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local FameChecker = require("src.core.game3.fame_checker")
local TextIR = require("src.core.game3.scripting.text_ir")
local Strings = require("src.core.Strings")

local FameCheckerUi = {}

local PERSON = FameChecker.PERSON
local PICK = FameChecker.PICKSTATE
local NSLOT = FameChecker.NUM_FLAVOR_TEXTS

local CACHE_SUB = "fame_checker"

-- pokefirered/src/fame_checker.c:1576 FC_PopulateListMenu
local MAX_SHOWED = 5
-- pokefirered/src/fame_checker.c:1524 FC_DoMoveCursor
local ROW_H = 14

-- pokefirered/src/fame_checker.c:474 sUIWindowTemplates
local LIST_WIN = { 1, 3, 8, 10 }
local HELP_WIN = { 6, 0, 24, 2 }
local ICONDESC_WIN = { 15, 10, 11, 4 }

-- pokefirered/src/fame_checker.c:1339 PERSON_X / PERSON_Y
local PERSON_X, PERSON_Y = 148, 66
local PORTRAIT = 64

-- pokefirered/src/fame_checker.c:171 sFameCheckerTrainerPicIdxs
local TRAINER_PIC = {
  [0] = 86, 84, 116, 117, 118, 119, 120, 122, 121, 112, 113, 114, 115, 100, 123, 108,
}

-- pokefirered/src/fame_checker.c:1342 CreatePersonPicSprite
local OWN_ART = {
  [PERSON.OAK] = true,
  [PERSON.DAISY] = true,
  [PERSON.BILL] = true,
  [PERSON.MRFUJI] = true,
}

-- pokefirered/src/fame_checker.c:265 sFameCheckerArrayNpcGraphicsIds
local ICON_GFX = {
  [0] = { [0] = 103, 71, 48, 105, 75, 55 },
  [1] = { [0] = 55, 48, 61, 105, 35, 105 },
  [2] = { [0] = 102, 80, 27, 19, 30, 105 },
  [3] = { [0] = 102, 81, 43, 39, 29, 105 },
  [4] = { [0] = 102, 82, 61, 61, 62, 105 },
  [5] = { [0] = 102, 83, 22, 29, 83, 105 },
  [6] = { [0] = 102, 84, 26, 22, 105, 30 },
  [7] = { [0] = 102, 25, 85, 85, 105, 41 },
  [8] = { [0] = 102, 86, 55, 28, 105, 105 },
  [9] = { [0] = 77, 77, 32, 105, 17, 35 },
  [10] = { [0] = 79, 79, 105, 54, 29, 54 },
  [11] = { [0] = 75, 54, 54, 105, 75, 35 },
  [12] = { [0] = 74, 74, 24, 23, 105, 41 },
  [13] = { [0] = 72, 18, 32, 89, 89, 89 },
  [14] = { [0] = 17, 49, 105, 30, 105, 105 },
  [15] = { [0] = 87, 55, 55, 87, 91, 55 },
}

FameCheckerUi.open = false
FameCheckerUi.mode = "top"
FameCheckerUi.pickMode = false
FameCheckerUi.cursor = 1
FameCheckerUi.scroll = 0
FameCheckerUi.iconCursor = 0
FameCheckerUi.textPage = 1

local function lazyModule(name)
  local mod
  return function()
    if mod == nil then
      local ok, m = pcall(require, name)
      mod = (ok and m) or false
    end
    return mod or nil
  end
end

local owSprites = lazyModule("src.core.game3.ow_sprites")
local bagChrome = lazyModule("src.ui.game3.bag_chrome")
local pokedexChrome = lazyModule("src.ui.game3.pokedex_chrome")

local function se(id)
  pcall(function()
    local Audio = require("src.core.game3.audio")
    if Audio and Audio.playSe then Audio.playSe(id) end
  end)
end

local function read_bytes(rel)
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local ok, d = pcall(function() return Dataset.cache():read(rel) end)
    if ok and type(d) == "string" and #d > 0 then return d end
  end
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if okC and CacheFs and CacheFs.readActive then
    local ok, d = pcall(CacheFs.readActive, rel)
    if ok and type(d) == "string" and #d > 0 then return d end
  end
  if love and love.filesystem and love.filesystem.read then
    local ok, d = pcall(love.filesystem.read, rel)
    if ok and type(d) == "string" and #d > 0 then return d end
  end
  local f = io.open(rel, "rb")
  if f then
    local d = f:read("*a")
    f:close()
    if d and #d > 0 then return d end
  end
  return nil
end

local function cache_root()
  local okE, Extract = pcall(require, "src.import.gba.extract_island1")
  local root = (okE and Extract and Extract.CACHE_ROOT) or "data/generated/gba"
  return root
end

local function art_root()
  return cache_root() .. "/" .. CACHE_SUB
end

local function rgba_to_image(rgba, w, h)
  if not (love and love.image and love.graphics) then return nil end
  if not rgba or #rgba < w * h * 4 then return nil end
  local okI, data = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if not (okI and data) then return nil end
  local okG, img = pcall(love.graphics.newImage, data)
  if not okG then return nil end
  if img.setFilter then img:setFilter("nearest", "nearest") end
  return img
end

FameCheckerUi._images = {}

local function art(key, rel, w, h)
  if FameCheckerUi._images[key] == nil then
    local bytes = read_bytes(art_root() .. "/" .. rel)
    FameCheckerUi._images[key] = (bytes and rgba_to_image(bytes, w, h)) or false
  end
  return FameCheckerUi._images[key] or nil
end

function FameCheckerUi.background()
  return art("bg", "bg.rgba", 240, 160)
end

function FameCheckerUi.pack()
  if FameCheckerUi._packTried then return FameCheckerUi._pack end
  FameCheckerUi._packTried = true
  local src = read_bytes(art_root() .. "/pack.lua")
  if not src then return nil end
  local chunk = load(src, "@fame_checker/pack.lua", "t", {})
  if not chunk then return nil end
  local ok, pack = pcall(chunk)
  if ok and type(pack) == "table" then FameCheckerUi._pack = pack end
  return FameCheckerUi._pack
end

function FameCheckerUi.reloadAssets()
  FameCheckerUi._images = {}
  FameCheckerUi._pack = nil
  FameCheckerUi._packTried = nil
  FameCheckerUi._names = {}
  FameCheckerUi._pageMemo = {}
  FameCheckerUi._rows = nil
  FameCheckerUi._icons = {}
  FameCheckerUi._view = nil
end

-- pokefirered/src/fame_checker.c:1342 CreatePersonPicSprite
function FameCheckerUi.portraitSource(person)
  local p = tonumber(person)
  if not p or not TRAINER_PIC[p] then return nil, nil end
  if OWN_ART[p] then return "art", art_root() .. "/" .. p .. ".rgba" end
  return "trainer", cache_root() .. "/trainers/front/" .. TRAINER_PIC[p] .. ".rgba"
end

function FameCheckerUi.portrait(person)
  local source, rel = FameCheckerUi.portraitSource(person)
  if not source then return nil, nil end
  local key = source .. rel
  if FameCheckerUi._images[key] == nil then
    local bytes = read_bytes(rel)
    FameCheckerUi._images[key] = (bytes and rgba_to_image(bytes, PORTRAIT, PORTRAIT)) or false
  end
  local img = FameCheckerUi._images[key] or nil
  if img then return img, source end
  return nil, nil
end

-- pokefirered/src/strings.c:1272
local function nonTrainerName(person)
  if person == PERSON.OAK then return Strings("OAK") end
  if person == PERSON.DAISY then return Strings("DAISY") end
  if person == PERSON.BILL then return Strings("BILL") end
  if person == PERSON.MRFUJI then return Strings("FUJI") end
  return nil
end

FameCheckerUi._names = {}

-- pokefirered/src/fame_checker.c:1546 FC_PopulateListMenu
function FameCheckerUi.personName(person)
  local p = tonumber(person)
  if not p then return "" end
  local memo = FameCheckerUi._names[p]
  if memo then return memo end
  local name = FameCheckerUi._personName(p)
  FameCheckerUi._names[p] = name
  return name
end

function FameCheckerUi._personName(p)
  local pack = FameCheckerUi.pack()
  local fromPack = pack and pack.listNames and pack.listNames[p]
  if type(fromPack) == "string" and fromPack ~= "" then return fromPack end
  local trainerId = FameChecker.TRAINER_IDS[p]
  if trainerId and trainerId < FameChecker.NON_TRAINER_START then
    local okT, Trainers = pcall(require, "src.core.game3.scripting.trainers")
    if okT and Trainers and Trainers.info then
      local okI, info = pcall(Trainers.info, trainerId)
      if okI and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
        return info.name
      end
    end
  end
  return nonTrainerName(p) or ""
end

local function textCtx()
  local session = FameCheckerUi._session
  return {
    playerName = (session and (session.name or session.playerName)) or "PLAYER",
    rivalName = (session and (session.rivalName or session.rival)) or "RIVAL",
  }
end

FameCheckerUi._pageMemo = {}

local function pages(text)
  if type(text) ~= "string" or text == "" then return nil end
  local memo = FameCheckerUi._pageMemo[text]
  if memo ~= nil then
    if memo == false then return nil end
    return memo
  end
  local ir = TextIR.fromAscii(text)
  local ctx = textCtx()
  local out, idx, kind = {}, 1, nil
  repeat
    local page
    page, idx, kind = TextIR.expandPage(ir, idx, ctx)
    if page and page ~= "" then out[#out + 1] = page end
  until kind == "eos" or not kind
  if #out < 1 then
    FameCheckerUi._pageMemo[text] = false
    return nil
  end
  FameCheckerUi._pageMemo[text] = out
  return out
end

-- pokefirered/src/fame_checker.c:246 sFameCheckerFlavorTextPointers
function FameCheckerUi.flavorText(person, slot)
  local pack = FameCheckerUi.pack()
  local rows = pack and pack.flavorText and pack.flavorText[tonumber(person)]
  if type(rows) ~= "table" then return nil end
  local text = rows[tonumber(slot)]
  if type(text) ~= "string" or text == "" then return nil end
  return text
end

-- pokefirered/src/fame_checker.c:209 sFameCheckerNameAndQuotesPointers
function FameCheckerUi.pickModeText(person)
  local p = tonumber(person)
  if not p then return nil end
  local pack = FameCheckerUi.pack()
  if not pack then return nil end
  local all = FameChecker.hasUnlockedAllFlavorTexts(FameCheckerUi._session, p)
  local rows = all and pack.quotes or pack.names
  local text = type(rows) == "table" and rows[p] or nil
  if type(text) ~= "string" or text == "" then return nil end
  return text
end

-- pokefirered/src/fame_checker.c:1395 UpdateIconDescriptionBox
function FameCheckerUi.iconDescription(person, slot)
  local pack = FameCheckerUi.pack()
  if not pack then return nil, nil end
  local p, s = tonumber(person), tonumber(slot)
  local loc = pack.originLocation and pack.originLocation[p] and pack.originLocation[p][s]
  local obj = pack.originObject and pack.originObject[p] and pack.originObject[p][s]
  if type(loc) ~= "string" then loc = nil end
  if type(obj) ~= "string" then obj = nil end
  return loc, obj
end

FameCheckerUi._rows = nil

-- pokefirered/src/fame_checker.c:1546 FC_PopulateListMenu
function FameCheckerUi.rows()
  local list = FameChecker.unlockedPersons(FameCheckerUi._session)
  local rows = {}
  for i = 1, #list do
    rows[i] = { person = list[i], label = FameCheckerUi.personName(list[i]) }
  end
  -- pokefirered/src/strings.c:128 gFameCheckerText_Cancel
  rows[#rows + 1] = { cancel = true, label = Strings("CANCEL") }
  FameCheckerUi._rows = rows
  FameCheckerUi._view = nil
  return rows
end

local function cachedRows()
  return FameCheckerUi._rows or FameCheckerUi.rows()
end

function FameCheckerUi.selectedRow()
  local rows = cachedRows()
  return rows[FameCheckerUi.cursor], rows
end

-- pokefirered/src/fame_checker.c:1576 FC_PopulateListMenu
local function maxShowed(total)
  if total < MAX_SHOWED then return total end
  return MAX_SHOWED
end

function FameCheckerUi.selectedPerson()
  local row = FameCheckerUi.selectedRow()
  if row and row.person then return row.person end
  return nil
end

FameCheckerUi._icons = {}

-- pokefirered/src/fame_checker.c:1099 CreateAllFlavorTextIcons
function FameCheckerUi.icons(person)
  local p = tonumber(person)
  local out = {}
  for slot = 0, NSLOT - 1 do
    local unlocked = p ~= nil
      and FameChecker.hasFlavorText(FameCheckerUi._session, p, slot) or false
    out[slot] = {
      unlocked = unlocked,
      graphicsId = unlocked and ICON_GFX[p] and ICON_GFX[p][slot] or nil,
    }
  end
  if p ~= nil then FameCheckerUi._icons[p] = out end
  return out
end

local function cachedIcons(person)
  local p = tonumber(person)
  if p == nil then return nil end
  return FameCheckerUi._icons[p] or FameCheckerUi.icons(p)
end

function FameCheckerUi.personHasUnlockedPanels(person)
  local p = tonumber(person)
  if not p then return false end
  for slot = 0, NSLOT - 1 do
    if FameChecker.hasFlavorText(FameCheckerUi._session, p, slot) then return true end
  end
  return false
end

-- pokefirered/src/fame_checker.c:1074 PrintUIHelp
function FameCheckerUi.helpText()
  if FameCheckerUi.mode == "flavor" then
    -- pokefirered/src/strings.c:1271 gFameCheckerText_FlavorTextUI
    return Strings("{DPAD_ANY}PICK {A_BUTTON}READ {B_BUTTON}CANCEL")
  end
  if FameCheckerUi.pickMode
      or not FameCheckerUi.personHasUnlockedPanels(FameCheckerUi.selectedPerson()) then
    -- pokefirered/src/strings.c:1270 gFameCheckerText_PickScreenUI
    return Strings("{START_BUTTON}PICK {DPAD_UPDOWN}SELECT {B_BUTTON}CANCEL")
  end
  -- pokefirered/src/strings.c:1269 gFameCheckerText_MainScreenUI
  return Strings("{START_BUTTON}PICK {DPAD_UPDOWN}SELECT {A_BUTTON}OK")
end

local function clamp_cursor()
  local total = #cachedRows()
  local shown = maxShowed(total)
  if FameCheckerUi.cursor > total then FameCheckerUi.cursor = total end
  if FameCheckerUi.cursor < 1 then FameCheckerUi.cursor = 1 end
  if FameCheckerUi.scroll > total - shown then FameCheckerUi.scroll = total - shown end
  if FameCheckerUi.scroll < 0 then FameCheckerUi.scroll = 0 end
  if FameCheckerUi.cursor <= FameCheckerUi.scroll then
    FameCheckerUi.scroll = FameCheckerUi.cursor - 1
  end
  if FameCheckerUi.cursor > FameCheckerUi.scroll + shown then
    FameCheckerUi.scroll = FameCheckerUi.cursor - shown
  end
  if FameCheckerUi.scroll < 0 then FameCheckerUi.scroll = 0 end
end

-- pokefirered/src/list_menu.c:438 ListMenuUpdateSelectedRowIndexAndScrollOffset
local function listStep(movingDown)
  local total = #cachedRows()
  local shown = maxShowed(total)
  local scroll = FameCheckerUi.scroll
  local itemsAbove = FameCheckerUi.cursor - 1 - scroll
  local newRow
  if not movingDown then
    if shown == 1 then
      newRow = 0
    else
      newRow = shown - (math.floor(shown / 2) + shown % 2) - 1
    end
    if scroll == 0 then
      if itemsAbove == 0 then return false end
      FameCheckerUi.cursor = scroll + (itemsAbove - 1) + 1
      return true
    end
    if itemsAbove > newRow then
      FameCheckerUi.cursor = scroll + (itemsAbove - 1) + 1
      return true
    end
    scroll = scroll - 1
  else
    if shown == 1 then
      newRow = 0
    else
      newRow = math.floor(shown / 2) + shown % 2
    end
    if scroll == total - shown then
      if itemsAbove >= shown - 1 then return false end
      FameCheckerUi.cursor = scroll + (itemsAbove + 1) + 1
      return true
    end
    if itemsAbove < newRow then
      FameCheckerUi.cursor = scroll + (itemsAbove + 1) + 1
      return true
    end
    scroll = scroll + 1
  end
  FameCheckerUi.scroll = scroll
  FameCheckerUi.cursor = scroll + newRow + 1
  return true
end

-- pokefirered/src/fame_checker.c:950 GetPickModeText
-- pokefirered/src/fame_checker.c:1517 PrintCancelDescription
-- pokefirered/src/fame_checker.c:970 PrintSelectedNameInBrightGreen
function FameCheckerUi.messageText()
  local row = FameCheckerUi.selectedRow()
  if not row then return nil end
  if FameCheckerUi.mode == "flavor" then
    local pageList = FameCheckerUi._pages
    if not pageList then return nil end
    return pageList[FameCheckerUi.textPage]
  end
  if FameCheckerUi.pickMode then
    if not row.person then return nil end
    if FameChecker.pickState(FameCheckerUi._session, row.person) ~= PICK.COLORED then
      return nil
    end
    local text = FameCheckerUi.pickModeText(row.person)
    if not text then return FameCheckerUi.personName(row.person) end
    local pageList = pages(text)
    return pageList and pageList[1] or nil
  end
  if row.cancel then
    return require("src.core.game3.rom_text").plain("gFameCheckerText_FameCheckerWillBeClosed")
  end
  return nil
end

local function rebuild_flavor_pages()
  local person = FameCheckerUi.selectedPerson()
  local slot = FameCheckerUi.iconCursor
  FameCheckerUi.textPage = 1
  if person == nil or not FameChecker.hasFlavorText(FameCheckerUi._session, person, slot) then
    FameCheckerUi._pages = nil
    return
  end
  FameCheckerUi._pages = pages(FameCheckerUi.flavorText(person, slot))
    or { FameCheckerUi.personName(person) }
end

function FameCheckerUi.isOpen()
  return FameCheckerUi.open
end

-- pokefirered/src/fame_checker.c:625 UseFameChecker
function FameCheckerUi.show(session, opts)
  opts = opts or {}
  FameCheckerUi._session = session
  FameCheckerUi._onDone = opts.onDone
  FameCheckerUi._fromBag = opts.fromBag and true or false
  FameCheckerUi._names = {}
  FameCheckerUi._pageMemo = {}
  FameCheckerUi._rows = nil
  FameCheckerUi._icons = {}
  FameCheckerUi._view = nil
  FameCheckerUi.open = true
  FameCheckerUi.mode = "top"
  FameCheckerUi.pickMode = false
  FameCheckerUi.cursor = 1
  FameCheckerUi.scroll = 0
  FameCheckerUi.iconCursor = 0
  FameCheckerUi.textPage = 1
  FameCheckerUi._pages = nil
  clamp_cursor()
  se(199)
  Stack.push("fame_checker", FameCheckerUi, { hideBelow = true })
  return true
end

-- pokefirered/src/fame_checker.c:1010 Task_StartToCloseFameChecker
function FameCheckerUi.close()
  if not FameCheckerUi.open then return false end
  se(199)
  FameCheckerUi.open = false
  FameCheckerUi.mode = "top"
  FameCheckerUi.pickMode = false
  FameCheckerUi._pages = nil
  FameCheckerUi._rows = nil
  FameCheckerUi._icons = {}
  FameCheckerUi._view = nil
  Stack.pop("fame_checker")
  local cb = FameCheckerUi._onDone
  FameCheckerUi._onDone = nil
  FameCheckerUi._session = nil
  if cb then cb() end
  return true
end

-- pokefirered/src/fame_checker.c:805 TryExitPickMode
local function tryExitPickMode()
  if not FameCheckerUi.pickMode then return false end
  FameCheckerUi.pickMode = false
  return true
end

-- pokefirered/src/fame_checker.c:729 Task_TopMenuHandleInput
local function moveListCursor(movingDown)
  if not listStep(movingDown) then return end
  FameCheckerUi.iconCursor = 0
  se(5)
end

-- pokefirered/src/fame_checker.c:861 Task_FlavorTextDisplayHandleInput
local function moveIconCursor(delta)
  local slot = FameCheckerUi.iconCursor
  if delta == "updown" then
    if slot >= 3 then slot = slot - 3 else slot = slot + 3 end
  elseif delta == "left" then
    if slot % 3 == 0 then slot = slot + 2 else slot = slot - 1 end
  elseif delta == "right" then
    if (slot + 1) % 3 == 0 then slot = slot - 2 else slot = slot + 1 end
  end
  FameCheckerUi.iconCursor = slot
  se(187)
  rebuild_flavor_pages()
end

function FameCheckerUi.handleInput(input)
  if not FameCheckerUi.open then return end

  if FameCheckerUi.mode == "flavor" then
    if input:wasPressed("b") then
      se(5)
      FameCheckerUi.mode = "top"
      FameCheckerUi._pages = nil
      return
    end
    if input:wasPressed("up") or input:wasPressed("down") then
      moveIconCursor("updown")
    elseif input:wasPressed("left") then
      moveIconCursor("left")
    elseif input:wasPressed("right") then
      moveIconCursor("right")
    elseif input:wasPressed("a") then
      local pageList = FameCheckerUi._pages
      if pageList then
        if FameCheckerUi.textPage < #pageList then
          FameCheckerUi.textPage = FameCheckerUi.textPage + 1
        else
          FameCheckerUi.textPage = 1
        end
      end
    end
    return
  end

  local row = FameCheckerUi.selectedRow()
  if input:wasPressed("select") then
    if not FameCheckerUi.pickMode and not FameCheckerUi._fromBag then
      FameCheckerUi.close()
    end
    return
  end
  if input:wasPressed("start") then
    if tryExitPickMode() then
      se(203)
    elseif row and row.person then
      se(203)
      FameCheckerUi.pickMode = true
    end
    return
  end
  if input:wasPressed("a") then
    if row and row.cancel then
      FameCheckerUi.close()
    elseif FameCheckerUi.pickMode then
      return
    elseif row and FameCheckerUi.personHasUnlockedPanels(row.person) then
      se(5)
      FameCheckerUi.mode = "flavor"
      rebuild_flavor_pages()
    end
    return
  end
  if input:wasPressed("b") then
    if not tryExitPickMode() then FameCheckerUi.close() end
    return
  end
  if input:wasPressed("up") then
    moveListCursor(false)
  elseif input:wasPressed("down") then
    moveListCursor(true)
  end
end

local function iconCenter(slot)
  return 47 * (slot % 3) + 0x72, 27 * math.floor(slot / 3) + 0x2F
end

-- pokefirered/src/fame_checker.c:1281 PlaceQuestionMarkTile
local function questionCenter(slot)
  return 47 * (slot % 3) + 0x72, 27 * math.floor(slot / 3) + 0x1F
end

-- pokefirered/src/fame_checker.c:1264 CreateFlavorTextIconSelectorCursorSprite
local function selectorCenter(slot)
  return 114 + 47 * (slot % 3), 34 + 27 * (slot >= 3 and 1 or 0)
end

local function draw_icons(person)
  local OwSprites = owSprites()
  local icons = cachedIcons(person)
  for slot = 0, NSLOT - 1 do
    local icon = icons[slot]
    if icon.unlocked then
      local cx, cy = iconCenter(slot)
      local drawn = false
      if OwSprites and OwSprites.get and icon.graphicsId then
        local spr = OwSprites.get(icon.graphicsId)
        local quad = spr and spr.quads and spr.quads[0]
        if spr and quad then
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(spr.image, quad, cx - spr.width / 2, cy - spr.height / 2)
          drawn = true
        end
      end
      if not drawn then
        love.graphics.setColor(0.86, 0.88, 0.92, 1)
        love.graphics.rectangle("fill", cx - 8, cy - 12, 16, 24)
        love.graphics.setColor(1, 1, 1, 1)
      end
    else
      local mark = art("question", "question_mark.rgba", 16, 32)
      if mark then
        local qx, qy = questionCenter(slot)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(mark, qx - 8, qy - 16)
      else
        local cx, cy = iconCenter(slot)
        FrlgFont.draw("?", cx - 4, cy - 7, { colors = FrlgFont.COLOR.WHITE })
      end
    end
  end
end

local function draw_portrait(person)
  local img, source = FameCheckerUi.portrait(person)
  local x, y = PERSON_X - PORTRAIT / 2, PERSON_Y - PORTRAIT / 2
  local silhouette =
    FameChecker.pickState(FameCheckerUi._session, person) == PICK.SILHOUETTE
  if not img then
    love.graphics.setColor(0.13, 0.16, 0.22, 1)
    love.graphics.rectangle("fill", x, y, PORTRAIT, PORTRAIT)
    love.graphics.setColor(1, 1, 1, 1)
    FrlgFont.draw(FameCheckerUi.personName(person), x + 2, y + PORTRAIT / 2 - 7,
      { maxWidth = PORTRAIT - 4, colors = FrlgFont.COLOR.WHITE })
    return source
  end
  -- pokefirered/src/fame_checker.c:1374 sSilhouettePalette
  if silhouette then
    local PokedexChrome = pokedexChrome()
    if PokedexChrome and PokedexChrome.drawSilhouette then
      PokedexChrome.drawSilhouette(img, x, y)
      love.graphics.setColor(1, 1, 1, 1)
      return source
    end
    love.graphics.setColor(0.29, 0.29, 0.29, 1)
    love.graphics.draw(img, x, y)
    love.graphics.setColor(1, 1, 1, 1)
    return source
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, x, y)
  return source
end

local function view()
  local v = FameCheckerUi._view
  if v and v.rows == FameCheckerUi._rows
      and v.cursor == FameCheckerUi.cursor and v.scroll == FameCheckerUi.scroll
      and v.mode == FameCheckerUi.mode and v.pickMode == FameCheckerUi.pickMode
      and v.iconCursor == FameCheckerUi.iconCursor
      and v.textPage == FameCheckerUi.textPage
      and v.pages == FameCheckerUi._pages then
    return v
  end
  local rows = cachedRows()
  local row = rows[FameCheckerUi.cursor]
  local person = row and row.person or nil
  local msg = FameCheckerUi.messageText()
  local loc, obj
  if FameCheckerUi.mode == "flavor" and person ~= nil
      and FameChecker.hasFlavorText(FameCheckerUi._session, person, FameCheckerUi.iconCursor) then
    loc, obj = FameCheckerUi.iconDescription(person, FameCheckerUi.iconCursor)
  end
  v = {
    rows = rows,
    cursor = FameCheckerUi.cursor,
    scroll = FameCheckerUi.scroll,
    mode = FameCheckerUi.mode,
    pickMode = FameCheckerUi.pickMode,
    iconCursor = FameCheckerUi.iconCursor,
    textPage = FameCheckerUi.textPage,
    pages = FameCheckerUi._pages,
    row = row,
    person = person,
    icons = person ~= nil and cachedIcons(person) or nil,
    help = FameCheckerUi.helpText(),
    msg = msg and FrlgFont.wrap(msg, 200) or nil,
    loc = loc,
    obj = obj,
    listWin = Window.template(LIST_WIN[1], LIST_WIN[2], LIST_WIN[3], LIST_WIN[4]),
    descWin = Window.template(ICONDESC_WIN[1], ICONDESC_WIN[2],
      ICONDESC_WIN[3], ICONDESC_WIN[4]),
  }
  FameCheckerUi._view = v
  return v
end

-- pokefirered/src/fame_checker.c:1588 FC_CreateScrollIndicatorArrowPair
local ARROW_X, ARROW_UP_Y, ARROW_DOWN_Y = 40, 26, 100

local function draw_scroll_arrows(total)
  if total <= MAX_SHOWED then return end
  local BagChrome = bagChrome()
  if not (BagChrome and BagChrome.drawArrow) then return end
  if FameCheckerUi.scroll > 0 then
    BagChrome.drawArrow("up", ARROW_X - 8, ARROW_UP_Y - 8)
  end
  if FameCheckerUi.scroll < total - MAX_SHOWED then
    BagChrome.drawArrow("down", ARROW_X - 8, ARROW_DOWN_Y - 8)
  end
end

function FameCheckerUi.draw()
  if not FameCheckerUi.open then return end
  if not (love and love.graphics) then return end

  local v = view()

  local bg = FameCheckerUi.background()
  if bg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(bg, 0, 0)
  else
    love.graphics.setColor(0.16, 0.24, 0.38, 1)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
    love.graphics.setColor(1, 1, 1, 1)
    Window.stdFrame(v.listWin)
  end

  for i = 1, MAX_SHOWED do
    local idx = FameCheckerUi.scroll + i
    local entry = v.rows[idx]
    if not entry then break end
    local y = LIST_WIN[2] * 8 + 4 + (i - 1) * ROW_H
    if idx == FameCheckerUi.cursor and FameCheckerUi.mode == "top" then
      Window.cursorPx(LIST_WIN[1] * 8, y)
    end
    FrlgFont.draw(entry.label, LIST_WIN[1] * 8 + 8, y,
      { maxWidth = LIST_WIN[3] * 8 - 8,
        colors = idx == FameCheckerUi.cursor and FrlgFont.COLOR.GREEN or FrlgFont.COLOR.NORMAL })
  end
  draw_scroll_arrows(#v.rows)

  local person = v.person
  if person ~= nil then
    -- pokefirered/src/fame_checker.c:454 sUIBgTemplates BG1 priority 0 hides the icons
    if FameCheckerUi.pickMode then
      draw_portrait(person)
    else
      draw_icons(person)
    end
    if FameCheckerUi.mode == "flavor" then
      local cx, cy = selectorCenter(FameCheckerUi.iconCursor)
      local cursorArt = art("cursor", "cursor.rgba", 32, 32)
      if cursorArt then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(cursorArt, cx - 16, cy - 16)
      else
        love.graphics.setColor(1, 0.85, 0.24, 1)
        love.graphics.rectangle("line", cx - 16.5, cy - 4.5, 33, 33)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end
  end

  -- pokefirered/src/fame_checker.c:986 Setup_DrawMsgAndListBoxes
  Window.dialogueFrame()
  if v.msg then
    FrlgFont.draw(v.msg, 24, 124,
      { maxWidth = 200, linePitch = 15, colors = FrlgFont.COLOR.NORMAL })
  end

  -- pokefirered/src/fame_checker.c:1074 PrintUIHelp
  local PokedexChrome = pokedexChrome()
  if PokedexChrome and PokedexChrome.drawControlInfo then
    PokedexChrome.drawControlInfo(v.help, HELP_WIN[1] * 8 + 188, 0)
  else
    local width = FrlgFont.measure(v.help, { small = true }) or 0
    FrlgFont.draw(v.help, HELP_WIN[1] * 8 + 188 - width, 0,
      { small = true, colors = FrlgFont.COLOR.WHITE })
  end

  -- pokefirered/src/fame_checker.c:1395 UpdateIconDescriptionBox
  if v.loc or v.obj then
    Window.stdFrame(v.descWin)
    local bx, by = ICONDESC_WIN[1] * 8, ICONDESC_WIN[2] * 8
    if v.loc then
      local w = FrlgFont.measure(v.loc, { small = true }) or 0
      FrlgFont.draw(v.loc, bx + (0x54 - w) / 2, by,
        { small = true, colors = FrlgFont.COLOR.DARK_GRAY })
    end
    if v.obj then
      local w = FrlgFont.measure(v.obj, { small = true }) or 0
      FrlgFont.draw(v.obj, bx + (0x54 - w) / 2, by + 10,
        { small = true, colors = FrlgFont.COLOR.DARK_GRAY })
    end
  end
end

return FameCheckerUi
