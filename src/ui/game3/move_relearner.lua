-- pokefirered/src/learn_move.c:476 MoveRelearnerStateMachine

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local Pokemon = require("src.core.game3.pokemon")
local MoveLearn = require("src.core.game3.move_learn")
local LearnMove = require("src.core.game3.battle.learn_move")
local SummaryChrome = require("src.ui.game3.summary_chrome")
local SummaryData = require("src.core.game3.summary_data")
local Strings = require("src.core.Strings")
local RomText = require("src.core.game3.rom_text")

local MoveRelearner = {}

MoveRelearner.open = false
MoveRelearner.state = "list"
MoveRelearner.cursor = 1
MoveRelearner.scroll = 0
MoveRelearner.yesNoCursor = 1

-- pokefirered/src/learn_move.c:339
local VISIBLE = 7
-- pokefirered/src/new_menu_helpers.c:84 FONT_NORMAL maxLetterHeight
local ROW_H = 14
local CACHE_SUB = "move_relearner"

-- pokefirered/src/learn_move.c:845 LoadMoveInfoUI
local LABEL_OPTS = { small = true, colors = FrlgFont.COLOR.DARK_GRAY }
local VALUE_OPTS = { colors = FrlgFont.COLOR.NORMAL }
local DESC_OPTS = { maxWidth = 116, linePitch = 14, colors = FrlgFont.COLOR.NORMAL }
local ROW_OPTS = { maxWidth = 72, colors = FrlgFont.COLOR.NORMAL }
local PROMPT_OPTS = { maxWidth = 204, linePitch = 15, colors = FrlgFont.COLOR.NORMAL }
-- pokefirered/src/learn_move.c:254 sWindowTemplates
local WIN_LIST = Window.template(19, 1, 10, 12)
local WIN_PROMPT = Window.template(2, 15, 26, 4)
-- pokefirered/src/learn_move.c:329 sMoveRelearnerYesNoMenuTemplate
local WIN_YESNO = Window.template(21, 8, 6, 4)

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

local function chrome_root()
  local okE, Extract = pcall(require, "src.import.gba.extract_island1")
  local root = (okE and Extract and Extract.CACHE_ROOT) or "data/generated/gba"
  return root .. "/" .. CACHE_SUB
end

-- pokefirered/src/learn_move.c:403 MoveRelearnerLoadBgGfx
function MoveRelearner.chrome()
  if MoveRelearner._chromeTried then return MoveRelearner._bg end
  MoveRelearner._chromeTried = true
  if not (love and love.image and love.graphics) then return nil end
  local rgba = read_bytes(chrome_root() .. "/bg.rgba")
  if not rgba or #rgba < 240 * 160 * 4 then return nil end
  local okI, data = pcall(love.image.newImageData, 240, 160)
  if not (okI and data) then return nil end
  local okW = pcall(function()
    for y = 0, 159 do
      for x = 0, 239 do
        local o = (y * 240 + x) * 4
        data:setPixel(x, y, rgba:byte(o + 1) / 255, rgba:byte(o + 2) / 255,
          rgba:byte(o + 3) / 255, rgba:byte(o + 4) / 255)
      end
    end
  end)
  if not okW then return nil end
  local okG, img = pcall(love.graphics.newImage, data)
  if not okG then return nil end
  MoveRelearner._bg = img
  return img
end

function MoveRelearner.isOpen()
  return MoveRelearner.open
end

function MoveRelearner.moves()
  return MoveRelearner._moves or {}
end

local function total_rows()
  return #MoveRelearner.moves() + 1
end

local function clamp_cursor()
  local total = total_rows()
  if MoveRelearner.cursor > total then MoveRelearner.cursor = total end
  if MoveRelearner.cursor < 1 then MoveRelearner.cursor = 1 end
  if MoveRelearner.cursor <= MoveRelearner.scroll then
    MoveRelearner.scroll = MoveRelearner.cursor - 1
  end
  if MoveRelearner.cursor > MoveRelearner.scroll + VISIBLE then
    MoveRelearner.scroll = MoveRelearner.cursor - VISIBLE
  end
  if MoveRelearner.scroll < 0 then MoveRelearner.scroll = 0 end
end

local function mon_name()
  return Pokemon.displayMonName(MoveRelearner._mon)
end

-- pokefirered/src/learn_move.c:690
local function to_list()
  MoveRelearner.state = "list"
  MoveRelearner.prompt = RomText.plain("gText_TeachWhichMoveToMon", { stringVars = { mon_name() } })
end

local function push_message(text, cb)
  MoveRelearner.state = "message"
  MoveRelearner.prompt = text
  MoveRelearner._messageCb = cb
end

local function ask_yes_no(text, cb)
  MoveRelearner.state = "yesno"
  MoveRelearner.prompt = text
  MoveRelearner.yesNoCursor = 1
  MoveRelearner._yesNoCb = cb
end

local function party_slot()
  local party = MoveRelearner._session and MoveRelearner._session.party
  if type(party) == "table" then
    for i = 1, #party do
      if party[i] == MoveRelearner._mon then return party, i end
    end
  end
  return { MoveRelearner._mon }, 1
end

-- pokefirered/src/learn_move.c:603 ShowSelectMovePokemonSummaryScreen
local function open_forget_screen(_labels, cb)
  local okS, SummaryMenu = pcall(require, "src.ui.game3.summary_menu")
  if not (okS and SummaryMenu and SummaryMenu.openMenu) then
    if cb then cb(nil) end
    return
  end
  local party, slot = party_slot()
  local okOpen = pcall(SummaryMenu.openMenu, party, slot, {
    session = MoveRelearner._session,
    mode = "select_move",
    moveToLearn = MoveRelearner._pendingMoveId,
    onSelectMove = function(slotIdx)
      if cb then cb(slotIdx) end
    end,
  })
  if not okOpen and cb then cb(nil) end
end

function MoveRelearner.finish(learned)
  if not MoveRelearner.open then return end
  MoveRelearner.open = false
  MoveRelearner.state = "list"
  MoveRelearner._messageCb = nil
  MoveRelearner._yesNoCb = nil
  Stack.pop("move_relearner")
  local cb = MoveRelearner._onDone
  MoveRelearner._onDone = nil
  if cb then cb(learned == true) end
end

-- pokefirered/src/learn_move.c:512
local function start_learn(moveId)
  MoveRelearner._pendingMoveId = moveId
  LearnMove.begin({
    mon = MoveRelearner._mon,
    moveId = moveId,
    relearner = true,
    displayName = mon_name(),
    pushMsg = push_message,
    askYesNo = ask_yes_no,
    askForget = open_forget_screen,
    onDone = function(learned)
      if learned then
        MoveRelearner.finish(true)
      else
        -- pokefirered/src/learn_move.c:591
        MoveRelearner._moves = MoveLearn.relearnableMoves(MoveRelearner._mon)
        clamp_cursor()
        to_list()
      end
    end,
  })
end

function MoveRelearner.show(mon, opts)
  opts = opts or {}
  MoveRelearner.open = true
  MoveRelearner._mon = mon
  MoveRelearner._session = opts.session
  MoveRelearner._onDone = opts.onDone
  MoveRelearner._moves = MoveLearn.relearnableMoves(mon)
  MoveRelearner._pendingMoveId = nil
  MoveRelearner._messageCb = nil
  MoveRelearner._yesNoCb = nil
  MoveRelearner.cursor = 1
  MoveRelearner.scroll = 0
  clamp_cursor()
  to_list()
  Stack.push("move_relearner", MoveRelearner, { hideBelow = true })
end

function MoveRelearner.handleInput(input)
  if not MoveRelearner.open then return end

  if MoveRelearner.state == "message" then
    if input:wasPressed("a") or input:wasPressed("b") then
      se(5)
      local cb = MoveRelearner._messageCb
      MoveRelearner._messageCb = nil
      to_list()
      if cb then cb() end
    end
    return
  end

  if MoveRelearner.state == "yesno" then
    if input:wasPressed("up") or input:wasPressed("down") then
      MoveRelearner.yesNoCursor = MoveRelearner.yesNoCursor == 1 and 2 or 1
      se(5)
    elseif input:wasPressed("a") then
      se(5)
      local yes = MoveRelearner.yesNoCursor == 1
      local cb = MoveRelearner._yesNoCb
      MoveRelearner._yesNoCb = nil
      to_list()
      if cb then cb(yes) end
    elseif input:wasPressed("b") then
      se(5)
      local cb = MoveRelearner._yesNoCb
      MoveRelearner._yesNoCb = nil
      to_list()
      if cb then cb(false) end
    end
    return
  end

  local total = total_rows()
  if input:wasPressed("up") then
    if MoveRelearner.cursor > 1 then
      MoveRelearner.cursor = MoveRelearner.cursor - 1
      clamp_cursor()
      se(5)
    end
  elseif input:wasPressed("down") then
    if MoveRelearner.cursor < total then
      MoveRelearner.cursor = MoveRelearner.cursor + 1
      clamp_cursor()
      se(5)
    end
  elseif input:wasPressed("a") then
    se(5)
    local moveId = MoveRelearner.moves()[MoveRelearner.cursor]
    if moveId then
      -- pokefirered/src/learn_move.c:784
      ask_yes_no(RomText.plain("gText_TeachMoveQues",
        { stringVars = { mon_name(), Pokemon.moveName(moveId) } }), function(yes)
        if yes then
          start_learn(moveId)
        else
          to_list()
        end
      end)
    else
      MoveRelearner.giveUpPrompt()
    end
  elseif input:wasPressed("b") then
    se(5)
    MoveRelearner.giveUpPrompt()
  end
end

-- pokefirered/src/learn_move.c:789
function MoveRelearner.giveUpPrompt()
  ask_yes_no(RomText.plain("gText_GiveUpTryingToTeachNewMove", { stringVars = { mon_name() } }), function(yes)
    if yes then
      -- pokefirered/src/learn_move.c:541
      MoveRelearner.finish(false)
    else
      to_list()
    end
  end)
end

-- pokefirered/src/learn_move.c:816 PrintMoveInfo
local function move_info(moveId)
  local info = MoveRelearner._info
  if info and info.id == moveId then return info end
  local row = Pokemon.battleMove(moveId) or {}
  local power = tonumber(row.power) or 0
  local acc = tonumber(row.accuracy) or 0
  local desc = SummaryData.moveDescription(moveId, Pokemon.moveName(moveId))
  info = {
    id = moveId,
    badge = tostring(row.type or "NORMAL"):upper(),
    power = power >= 2 and string.format("%3d", power) or "---",
    accuracy = acc > 0 and string.format("%3d", acc) or "---",
    pp = tostring(tonumber(row.pp) or 0),
    desc = (desc and desc ~= "") and FrlgFont.wrap(desc, 116) or nil,
  }
  MoveRelearner._info = info
  return info
end

local function draw_move_info(moveId)
  local info = move_info(moveId)
  SummaryChrome.drawTypeBadge(info.badge, 41, 4)
  FrlgFont.draw(info.power, 121, 4, VALUE_OPTS)
  FrlgFont.draw(info.accuracy, 121, 18, VALUE_OPTS)
  FrlgFont.draw(info.pp, 42, 18, VALUE_OPTS)
  if info.desc then
    FrlgFont.draw(info.desc, 17, 48, DESC_OPTS)
  end
end

function MoveRelearner.draw()
  if not MoveRelearner.open then return end
  if not (love and love.graphics) then return end
  local moves = MoveRelearner.moves()
  local total = total_rows()

  local bg = MoveRelearner.chrome()
  if bg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(bg, 0, 0)
  else
    love.graphics.setColor(0.24, 0.35, 0.50, 1)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
    -- pokefirered/src/learn_move.c:254 sWindowTemplates
    love.graphics.setColor(0.88, 0.91, 0.95, 1)
    love.graphics.rectangle("fill", 0, 0, 148, 48)
    love.graphics.setColor(0.98, 0.98, 0.98, 1)
    love.graphics.rectangle("fill", 16, 48, 120, 64)
    love.graphics.setColor(1, 1, 1, 1)
  end
  -- pokefirered/src/learn_move.c:679 DrawTextBorderOnWindows6and7
  Window.stdFrame(WIN_LIST)
  Window.stdFrame(WIN_PROMPT)

  -- pokefirered/src/learn_move.c:845 LoadMoveInfoUI
  FrlgFont.draw(Strings("TYPE"), 1, 4, LABEL_OPTS)
  FrlgFont.draw(Strings("POWER"), 80, 4, LABEL_OPTS)
  FrlgFont.draw(Strings("PP"), 1, 19, LABEL_OPTS)
  FrlgFont.draw(Strings("ACCURACY"), 80, 19, LABEL_OPTS)
  FrlgFont.draw(Strings("EFFECT"), 1, 34, LABEL_OPTS)

  local selected = moves[MoveRelearner.cursor]
  if selected then draw_move_info(selected) end

  -- pokefirered/src/learn_move.c:339 sMoveRelearnerListMenuTemplate
  for i = 1, VISIBLE do
    local idx = MoveRelearner.scroll + i
    if idx > total then break end
    local y = 8 + (i - 1) * ROW_H
    if idx == MoveRelearner.cursor and MoveRelearner.state == "list" then
      Window.cursorPx(152, y)
    end
    -- pokefirered/src/learn_move.c:761
    local row = moves[idx] and Pokemon.moveName(moves[idx]) or RomText.plain("gFameCheckerText_Cancel")
    FrlgFont.draw(row, 160, y, ROW_OPTS)
  end

  if MoveRelearner.prompt then
    FrlgFont.draw(MoveRelearner.prompt, 16, 122, PROMPT_OPTS)
  end

  if MoveRelearner.state == "yesno" then
    Window.stdFrame(WIN_YESNO)
    FrlgFont.draw(RomText.plain("gText_Yes"), 176, 66, VALUE_OPTS)
    FrlgFont.draw(RomText.plain("gText_No"), 176, 82, VALUE_OPTS)
    Window.cursorPx(169, MoveRelearner.yesNoCursor == 1 and 66 or 82)
  end
end

return MoveRelearner
