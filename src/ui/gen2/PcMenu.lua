-- The Pokemon PC's top menu (engine/pokemon/bills_pc_top.asm _BillsPC).
--
--   WITHDRAW POKéMON / DEPOSIT POKéMON / CHANGE BOX /
--   MOVE POKéMON W/O MAIL / MAIL BOX / SEE YA!
--
-- MAIL BOX is the item PC's PLAYERSPCITEM_MAIL_BOX row rather than one of
-- _BillsPC's five; it is here because this port used to fold both PCs into
-- one menu, and a directly-constructed PcMenu still folds them.  The
-- Pokecenter's whose-PC menu (src/ui/gen2/CenterPcMenu.lua) opens this as
-- BILL's PC with `bills = true`, which shows the cart's own five rows and
-- leaves the MAIL BOX to <PLAYER>'s PC (src/ui/gen2/ItemPcMenu.lua).
--
-- .MenuHeader is menu_coords 0, 0, 19, 17 -- the menu owns the whole screen,
-- with "What do you want to do?" in a text box along the bottom.  Choosing an
-- entry pushes BoxMenu (the withdraw/deposit list) or the box picker.
--
-- The assembled rows run through the ui.pc.items hook, the same name and the
-- same (game, items) payload the Gen 1 PC uses
-- (src/world/OverworldController.lua openPC), with SEE YA! appended after it
-- the way that site appends LOG OFF.

local Boxes = require("src.core.gen2.Boxes")
local Chrome = require("src.ui.gen2.Chrome")
local Logger = require("src.core.Logger")
local Mail = require("src.core.gen2.Mail")
local Runtime = require("src.mods.Runtime")
local Save = require("src.core.gen2.Save")
local SaveMenu = require("src.ui.gen2.SaveMenu")
local Screens = require("src.ui.Screens")
local Strings = require("src.core.Strings")

-- _PCMonHoldingMailText (data/text/common_2.asm), the refusal
-- BillsPC_MovePKMNMenu prints instead of opening the list.  Two pages, because
-- the ASM has a `para` in the middle of it.  Declared up here and looked up at
-- the call site, so Strings.source is what puts both in the catalog.
local MON_HOLDING_MAIL = {
  Strings.source("There is a POKéMON\nholding MAIL."),
  Strings.source("Please remove the\nMAIL."),
}

-- _ChangeBoxSaveText (data/text/common_2.asm:1306) is three lines whose `cont`
-- has already scrolled by the time YesNoBox goes up over its last two.
local CHANGE_BOX_SAVE = { "#MON BOX, data", "will be saved. OK?" }

-- YesNoBox's own `lb bc, SCREEN_WIDTH - 6, 7` (home/menu.asm:382-383).
local YESNO_X, YESNO_Y, YESNO_W, YESNO_H = 14, 7, 6, 5

local PcMenu = {}
PcMenu.__index = PcMenu
PcMenu.isOpaque = true

-- .strings, verbatim.  <PK> and <MN> are real font glyphs (codes $e1/$e2) and
-- Font.split matches charmap sequences, so writing them the way the ASM does
-- draws two tiles rather than seven -- which is the only reason "MOVE <PK><MN>
-- W/O MAIL" fits inside a 20-tile screen.
local ENTRIES = {
  { id = "withdraw", label = "WITHDRAW <PK><MN>" },
  { id = "deposit", label = "DEPOSIT <PK><MN>" },
  { id = "changebox", label = "CHANGE BOX" },
  { id = "move", label = "MOVE <PK><MN> W/O MAIL" },
  -- PLAYERSPCITEM_MAIL_BOX (engine/events/pokecenter_pc.asm), which BOTH
  -- .WhichPC lists carry: the MAILBOX is on the item PC in a Pokecenter and in
  -- the bedroom alike, unlike DECORATION below.  It sits here because this
  -- port folds the item PC's menu into the storage one.
  { id = "mailbox", label = "MAIL BOX" },
  { id = "seeya", label = "SEE YA!" },
}

-- PLAYERSPCITEM_DECORATION, the one row the bedroom's PC has that a
-- Pokecenter's does not (engine/events/pokecenter_pc.asm: PLAYERSPC_HOUSE
-- carries it, PLAYERSPC_NORMAL does not).  It belongs to the item PC's menu on
-- the cart, which this port folds into the storage menu the same way both PCs
-- are folded -- so it hangs off the same list, gated on `house`.
local DECORATION = { id = "decoration", label = "DECORATION" }

-- The exit row.  It is a member of ENTRIES (it is one of _BillsPC's five), but
-- the list is assembled without it and it is put back on the end AFTER the
-- ui.pc.items hook has run, exactly as the Gen 1 site appends LOG OFF
-- (src/world/OverworldController.lua openPC): a mod may add, drop or reorder
-- anything it likes and still cannot orphan the way out.
local EXIT_ID = "seeya"

-- ui.pc.items identity: an unhooked build hands its own list back.
local function sameItems(_, items) return items end

function PcMenu:wantsFillScale() return true end
function PcMenu:drawsWidescreen() return true end

-- opts: save, house (the bedroom's PC, which also does decorations), events
--       (the wEventFlags bitfield the decoration menu reads ownership from),
--       bills (_BillsPC's own five rows, no MAIL BOX: what the whose-PC
--       menu's BILL's PC entry opens, src/ui/gen2/CenterPcMenu.lua),
--       onClose(changedDecorations)
function PcMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, PcMenu)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.onClose = opts.onClose
  self.house = opts.house and true or false
  self.events = opts.events
  -- The same route the start menu's SAVE row takes (src/core/Game2.lua:435),
  -- so the save.write veto and the save.writing event fire here too.
  self.writer = opts.writer
    or (game and type(game.writeSave) == "function"
      and function() return game:writeSave() end)
    or Save.save
  self.saveExists = opts.saveExists
  -- The folded MAIL BOX row belongs to the item PC, and the whose-PC menu
  -- reaches that through <PLAYER>'s PC (src/ui/gen2/ItemPcMenu.lua), so
  -- BILL's PC shows the cart's own five rows.  The bedroom's PC keeps it: the
  -- MAILBOX is on both .WhichPC lists.
  local dropMailbox = opts.bills and not self.house
  local entries = {}
  for _, entry in ipairs(ENTRIES) do
    local drop = entry.id == EXIT_ID
      or (dropMailbox and entry.id == "mailbox")
    if not drop then entries[#entries + 1] = entry end
  end
  if self.house then
    entries[#entries + 1] = DECORATION
  end
  -- Same hook name and same (game, items) payload as the Gen 1 PC menu
  -- (src/world/OverworldController.lua openPC), so one mod source can add a
  -- row to both generations' PCs.  Unguarded, like that site: the list is
  -- built once per session, not per frame.  A hook that answers with anything
  -- but a table is degraded to the vanilla list.
  local hooked = Runtime.call("ui.pc.items", sameItems, game, entries)
  if type(hooked) == "table" then
    entries = hooked
  else
    Logger.error("ui.pc.items returned %s; keeping the vanilla items",
                 type(hooked))
  end
  -- SEE YA! goes back on last: it is the row B lands on, and TURN OFF sits at
  -- the bottom of the cart's house list too.
  for _, entry in ipairs(ENTRIES) do
    if entry.id == EXIT_ID then entries[#entries + 1] = entry end
  end
  self.entries = entries
  -- wChangedDecorations, carried out to `special PlayersHousePC` so its
  -- script's `iftrue` can reload the map.
  self.changedDecorations = false
  self.index = 1
  self.message = nil
  -- Whether clearing the message also logs off.  .CheckCanUsePC's does (the PC
  -- never opened at all); BillsPC_MovePKMNMenu's mail refusal does not -- its
  -- `.quit` returns with the carry clear, which drops back into the _BillsPC
  -- loop and redraws this menu.
  self.messageCloses = true
  -- .CheckCanUsePC: an empty party gets the "You'll need a POKéMON" line and
  -- the PC never opens.  Kept here rather than at the call site so every route
  -- into the PC (the overworld script, a driver, a mod) gets the same gate.
  local ok, reason = Boxes.canUsePc(self.save)
  if not ok then self.message = reason end
  return self
end

-- A refusal that leaves the PC open: the message replaces the menu until a
-- button clears it, and then the menu is back exactly where it was.  `pages`
-- is a list because a `para` in the ASM is a screenful of its own -- the text
-- box holds two rows and the fourth line of _PCMonHoldingMailText would
-- otherwise be drawn off the bottom of the screen.
function PcMenu:notice(pages)
  self.message = pages[1]
  self.messagePages = pages
  self.messagePage = 1
  self.messageCloses = false
end

function PcMenu:close()
  if self.onClose then self.onClose(self.changedDecorations) end
end

-- engine/pokemon/bills_pc.asm:2403 BillsPC_ChangeBoxSubmenu .Switch
-- engine/menus/save.asm:40 ChangeBoxSaveGame
function PcMenu:beginChangeBox(index)
  self.changeBox = index
  self.savePhase = "confirm"
  self.saveChoice = 1
  self.saveTimer = 0
  self.saved = nil
  local existed = self.saveExists
  if existed == nil then existed = Save.exists() end
  self.existed = existed
end

-- .refused: `pop de / ret`, with wCurBox untouched and the picker still up.
function PcMenu:refuseChangeBox()
  self.savePhase, self.changeBox = nil, nil
  self.saveTimer = 0
end

function PcMenu:acceptChangeBox()
  if self.saveChoice == 2 then return self:refuseChangeBox() end
  if self.savePhase == "confirm" and self.existed then
    self.savePhase = "overwrite"
    self.saveChoice = 1
    return
  end
  self.savePhase = "saving"
  self.saveTimer = 0
end

-- `pop de / ld a, e / ld [wCurBox], a` sits between SaveBox and
-- SavingDontTurnOffThePower, so the new index rides the file that is written.
function PcMenu:writeChangeBox()
  Boxes.setCurrent(self.save, self.changeBox)
  local ok = self.writer(self.save)
  self.saved = ok and true or false
  if ok then SaveMenu.playSaveSfx(self.game, SaveMenu.SFX_SAVE) end
end

function PcMenu:savePrompt()
  if self.savePhase == "overwrite" then return SaveMenu.OVERWRITE_PROMPT end
  if self.savePhase == "saving" then return SaveMenu.SAVING_PROMPT end
  if self.savePhase == "done" then
    if self.saved then
      local name = (self.save.player and self.save.player.name) or "GOLD"
      return { name .. " saved", "the game." }
    end
    return { "Could not save.", "" }
  end
  return CHANGE_BOX_SAVE
end

function PcMenu:updateChangeBox()
  -- SavingDontTurnOffThePower is DelayFrames, not a prompt: no button does
  -- anything until the sequence runs out (engine/menus/save.asm:55).
  if self.savePhase == "saving" then
    self.saveTimer = self.saveTimer + 1
    if self.saveTimer >= SaveMenu.SAVING_FRAMES then
      self:writeChangeBox()
      self.savePhase = "done"
      self.saveTimer = 0
    end
    return
  end
  if self.savePhase == "done" then
    self.saveTimer = self.saveTimer + 1
    if self.saveTimer >= SaveMenu.SAVED_FRAMES then
      self.savePhase, self.changeBox = nil, nil
      self.picking = false
    end
    return
  end

  local input = self.game and self.game.input
  if not input then return end
  if input:wasPressed("up") or input:wasPressed("down") then
    self.saveChoice = self.saveChoice == 1 and 2 or 1
  elseif input:wasPressed("a") then
    self:acceptChangeBox()
  elseif input:wasPressed("b") then
    -- B out of a yes/no is NO (InterpretTwoOptionMenu returns carry).
    self:refuseChangeBox()
  end
end

function PcMenu:choose()
  local entry = self.entries[self.index]
  if not entry then return end
  local game = self.game
  -- A hook- or monkey-patch-injected row carries label + onSelect and no id
  -- the ladder below knows, so without this arm it draws and does nothing.
  -- Same shape and same argument order as src/ui/gen2/PartyMenu.lua:433.
  if type(entry.onSelect) == "function" then
    entry.onSelect(self, game)
    return
  end
  if entry.id == "seeya" then
    self:close()
    return
  end
  if entry.id == "decoration" then
    if not (game and game.stack) then return end
    Screens.push(game, "Gen2DecorationMenu", {
      save = self.save,
      events = self.events,
      onDone = function(changed)
        self.changedDecorations = self.changedDecorations or changed or false
        game.stack:pop()
      end,
    })
    return
  end
  if entry.id == "mailbox" then
    if not (game and game.stack) then return end
    Screens.push(game, "Gen2MailboxMenu", {
      save = self.save,
      onClose = function() game.stack:pop() end,
    })
    return
  end
  if entry.id == "changebox" then
    self.picking = true
    self.pickIndex = self.save.currentBox or 1
    return
  end
  -- BillsPC_MovePKMNMenu asks IsAnyMonHoldingMail BEFORE it opens the list and
  -- refuses outright: MOVE POKéMON W/O MAIL is a whole-party operation, so one
  -- letter anywhere in the party stops it.
  if entry.id == "move" and Mail.anyMonHoldingMail(self.save) then
    self:notice({ Strings(MON_HOLDING_MAIL[1]), Strings(MON_HOLDING_MAIL[2]) })
    return
  end
  if not (game and game.stack) then return end
  Screens.push(game, "Gen2BoxMenu", {
    save = self.save,
    mode = entry.id, -- "withdraw" | "deposit" | "move"
    onClose = function() game.stack:pop() end,
  })
end

function PcMenu:update(_dt)
  local input = self.game and self.game.input
  if not input then return end

  if self.message then
    if input:wasPressed("a") or input:wasPressed("b") then
      local pages = self.messagePages
      if pages and self.messagePage < #pages then
        self.messagePage = self.messagePage + 1
        self.message = pages[self.messagePage]
        return
      end
      local closes = self.messageCloses
      self.message, self.messagePages, self.messagePage = nil, nil, nil
      self.messageCloses = true
      if closes then self:close() end
    end
    return
  end

  if self.savePhase then
    self:updateChangeBox()
    return
  end

  if self.picking then
    local total = Boxes.NUM_BOXES
    if input:wasPressed("up") then
      self.pickIndex = self.pickIndex > 1 and self.pickIndex - 1 or total
    elseif input:wasPressed("down") then
      self.pickIndex = self.pickIndex < total and self.pickIndex + 1 or 1
    elseif input:wasPressed("a") then
      if self.pickIndex == (self.save.currentBox or 1) then
        self.picking = false
      else
        self:beginChangeBox(self.pickIndex)
      end
    elseif input:wasPressed("b") then
      self.picking = false
    end
    return
  end

  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or #self.entries
  elseif input:wasPressed("down") then
    self.index = self.index < #self.entries and self.index + 1 or 1
  elseif input:wasPressed("a") then
    self:choose()
  elseif input:wasPressed("b") then
    self:close()
  end
end

function PcMenu:drawPanel()
  Chrome.clear()
  if self.message then
    Chrome.box(0, 12, 20, 6)
    -- A text box's two lines sit two tile rows apart, not one -- the same
    -- spacing src/render/TextBox.lua uses (line1 = ty+2, line2 = ty+4).
    local line = 14
    for part in (self.message .. "\n"):gmatch("(.-)\n") do
      Chrome.print(part, 1, line)
      line = line + 2
    end
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  if self.picking then
    -- CHANGE BOX: the 14 box names with how full each one is, six at a time.
    Chrome.box(0, 0, 20, 14)
    local rows = 6
    local scroll = math.max(0, math.min(self.pickIndex - rows,
      Boxes.NUM_BOXES - rows))
    for row = 1, rows do
      local i = row + scroll
      local ty = row * 2 - 1
      if i == self.pickIndex then Chrome.cursor(1, ty) end
      Chrome.print(Boxes.name(self.save, i), 2, ty)
      Chrome.printRight(
        ("%d/%d"):format(Boxes.count(self.save, i), Boxes.MONS_PER_BOX),
        18, ty)
    end
    if self.savePhase then
      -- ChangeBoxSaveGame's MenuTextbox, then YesNoBox over the box list.
      Chrome.box(0, 12, 20, 6)
      local lines = self:savePrompt()
      Chrome.print(lines[1] or "", 1, 14)
      Chrome.print(lines[2] or "", 1, 16)
      if self.savePhase == "confirm" or self.savePhase == "overwrite" then
        Chrome.box(YESNO_X, YESNO_Y, YESNO_W, YESNO_H)
        Chrome.print("YES", YESNO_X + 2, YESNO_Y + 1)
        Chrome.print("NO", YESNO_X + 2, YESNO_Y + 3)
        Chrome.cursor(YESNO_X + 1,
          YESNO_Y + (self.saveChoice == 1 and 1 or 3))
      end
      love.graphics.setColor(1, 1, 1, 1)
      return
    end
    Chrome.box(0, 14, 20, 4)
    Chrome.print("Which BOX?", 1, 16)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- .LogIn prints _PCWhatText into the (0,12) box, and that text is one word:
  -- "What?".  PrintText starts at (1,14).  The box goes down first because
  -- the menu window is drawn over it wherever a folded list runs past row 12,
  -- the way the cart's windows stack (src/ui/gen2/ItemPcMenu.lua does the
  -- same with the house's six-row item list).
  Chrome.box(0, 12, 20, 6)
  Chrome.print("What?", 1, 14)

  -- ClearPCItemScreen: Textbox at (0,0) with a 10x18 interior, and a second
  -- at (0,12) with a 4x18 one.  GetMenuTextStartCoord then puts the first
  -- label at (left+1+1, top+1+1) = (2,2) because STATICMENU_CURSOR is set and
  -- the menu does not ask for NO_TOP_SPACING; rows are two apart and the
  -- cursor sits one column left of the label.  _BillsPC's own five rows end
  -- at row 10 and fit that box exactly; the folded MAIL BOX (and the
  -- bedroom's DECORATION) put rows below it, so the window is sized to the
  -- list rather than to the five the cart ships.
  Chrome.box(0, 0, 20, math.max(12, #self.entries * 2 + 2))
  for i, entry in ipairs(self.entries) do
    local ty = i * 2
    if i == self.index then Chrome.cursor(1, ty) end
    Chrome.print(entry.label, 2, ty)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function PcMenu:draw()
  self:drawPanel()
end

function PcMenu:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

PcMenu.ENTRIES = ENTRIES

return PcMenu
