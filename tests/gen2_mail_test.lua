-- MAIL: the ten items, the `mailmsg` struct on a party slot, the PC's MAILBOX,
-- the compose keyboard's charset, and every refusal around a mon that is
-- carrying a letter.
--
-- ROM-free.  The model (src/core/gen2/Mail.lua) is love-free and takes its
-- state by argument, so most of this is plain table assertions; the four
-- screens need the same love stub the rest of the Gold menu suites use, and
-- none of them draw here.

package.path = "./?.lua;" .. package.path

love = love or {}
love.graphics = love.graphics or {
  getColor = function() return 1, 1, 1, 1 end,
  setColor = function() end,
  rectangle = function() end,
  print = function() end,
  printf = function() end,
  draw = function() end,
  newQuad = function() return {} end,
  newImage = function() return nil end,
  getShader = function() return nil end,
  setShader = function() end,
  newShader = function() error("no shaders in this harness") end,
  getDimensions = function() return 160, 144 end,
  push = function() end, pop = function() end,
  translate = function() end, scale = function() end,
  circle = function() end, clear = function() end,
  setLineWidth = function() end,
}
love.math = love.math or {
  random = function(a, b)
    if b then return a end
    return a and 1 or 0.5
  end,
}
love.image = love.image or {}
love.filesystem = love.filesystem or {
  load = function() return nil end,
  getInfo = function() return nil end,
  read = function() return nil end,
  write = function() return true end,
  remove = function() return true end,
}
love.timer = love.timer or { getTime = function() return 0 end }

-- No font is loaded here, so Font.encode would warn once per unknown glyph.
require("src.core.Logger").warn = function() end

local Boxes = require("src.core.gen2.Boxes")
local Breeding = require("src.core.gen2.Breeding")
local HeldItemMenu = require("src.ui.gen2.HeldItemMenu")
local Mail = require("src.core.gen2.Mail")
local MailCompose = require("src.ui.gen2.MailCompose")
local MailMenu = require("src.ui.gen2.MailMenu")
local MailRead = require("src.ui.gen2.MailRead")
local MailboxMenu = require("src.ui.gen2.MailboxMenu")
local PartyMenu = require("src.ui.gen2.PartyMenu")
local PcMenu = require("src.ui.gen2.PcMenu")
local Save = require("src.core.gen2.Save")
local Screens = require("src.ui.Screens")
local Typer = require("src.ui.gen2.Typer")

-- home/print_text.asm:1
local function typeOut(menu)
  for _ = 1, 600 do
    if not Typer.typing(menu) then return end
    menu:update()
  end
end

local failures, checks = 0, 0
local function check(name, got, want)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s, want %s"):format(
      name, tostring(got), tostring(want)))
  end
end

local function newInput()
  local input = { pressed = {} }
  function input:press(...)
    for _, button in ipairs({ ... }) do self.pressed[button] = true end
  end
  function input:wasPressed(button)
    if self.pressed[button] then
      self.pressed[button] = nil
      return true
    end
    return false
  end
  function input:isDown() return false end
  return input
end

local function newGame(save)
  local input = newInput()
  return {
    input = input,
    save = save,
    data = { audio = {}, pokemon = {}, items = {} },
    stack = { _items = {},
      push = function(self, s) self._items[#self._items + 1] = s end,
      pop = function(self) return table.remove(self._items) end,
      top = function(self) return self._items[#self._items] end,
    },
  }, input
end

-- A save with a party of `n` conscious mons and nothing else going on.
local function newSave(n)
  local save = Save.newGame({ playerName = "GOLD", trainerId = 1234 })
  for i = 1, n or 1 do
    save.party[i] = { species = "CYNDAQUIL", nickname = "MON" .. i, hp = 20,
                      maxHp = 20, level = 10 }
  end
  return save
end

-- ------------------------------------------------------------ ItemIsMail

-- data/items/mail_items.asm is a ten-entry list and ItemIsMail is a linear
-- search of it.  The two that matter are LITEBLUEMAIL and PORTRAITMAIL: a name
-- test for "_MAIL" -- which is what the port used before this landed -- misses
-- both, and a pocket test misses all ten (ItemAttributes puts mail in the
-- ordinary ITEM pocket).
check("ten mail items", #Mail.ITEMS, 10)
for _, id in ipairs(Mail.ITEMS) do
  check(id .. " is mail", Mail.isMail(id), true)
end
check("LITEBLUEMAIL is mail", Mail.isMail("LITEBLUEMAIL"), true)
check("PORTRAITMAIL is mail", Mail.isMail("PORTRAITMAIL"), true)
check("POTION is not", Mail.isMail("POTION"), false)
check("nil is not", Mail.isMail(nil), false)
-- A name that merely ends the right way is still not on the list.
check("a made-up _MAIL id is not", Mail.isMail("FAKE_MAIL"), false)

-- The *_MAIL_INDEX block is `const_def`, so 0-based and in the item order.
check("FLOWER_MAIL is index 0", Mail.INDEX.FLOWER_MAIL, 0)
check("MIRAGE_MAIL is index 9", Mail.INDEX.MIRAGE_MAIL, 9)

-- ------------------------------------------------------------- the struct

do
  local save = newSave(2)
  save.party[1].item = "FLOWER_MAIL"
  Mail.compose(save, 1, "HELLO", save.party[1], "FLOWER_MAIL")
  local entry = Mail.get(save, 1)
  check("compose stores the message", entry.message, "HELLO")
  check("with the player as author", entry.author, "GOLD")
  check("and the player's ID", entry.authorId, 1234)
  check("and the mon's species", entry.species, "CYNDAQUIL")
  check("and the stationery", entry.type, "FLOWER_MAIL")

  -- The buffer is MAIL_MSG_LENGTH bytes; anything past it never existed.
  local long = ("X"):rep(64)
  Mail.compose(save, 2, long, save.party[2], "SURF_MAIL")
  check("a message is trimmed to the buffer",
    #Mail.get(save, 2).message, Mail.MAIL_MSG_LENGTH)

  -- A slot outside sPartyMail's six structs is not a slot.
  check("slot 7 is refused", Mail.set(save, 7, Mail.entry("SURF_MAIL")), false)
  check("slot 0 is refused", Mail.set(save, 0, Mail.entry("SURF_MAIL")), false)
end

-- Mail.lines is MailGFX_PlaceMessage's two rows: a composed message has no
-- break in it and splits by width, a script's message carries its own.
do
  local wide = Mail.entry("FLOWER_MAIL", ("A"):rep(20))
  local top, bottom = Mail.lines(wide)
  check("a long message splits at MAIL_LINE_LENGTH", #top, 16)
  check("and the rest is the second row", #bottom, 4)
  local scripted = Mail.entry("FLOWER_MAIL", "DARK CAVE leads\nto another road")
  local a, b = Mail.lines(scripted)
  check("an explicit break wins", a, "DARK CAVE leads")
  check("and gives the second row", b, "to another road")
  local short = Mail.entry("FLOWER_MAIL", "HI")
  local s1, s2 = Mail.lines(short)
  check("a short message is one row", s1, "HI")
  check("with nothing under it", s2, "")
end

-- ---------------------------------------------------------- GivePokeMail

-- `ld a, [wPartyCount] / dec a`: the letter always lands on the LAST party
-- member, which is the mon the `givepoke` before it just added.
do
  local save = newSave(3)
  save.party[3].otName = "RANDY"
  save.party[3].otId = 518
  check("give lands on the last slot",
    Mail.give(save, "FLOWER_MAIL", "DARK CAVE leads\nto another road"), true)
  check("and hangs the item on that mon", save.party[3].item, "FLOWER_MAIL")
  check("with nothing on the first", save.party[1].item, nil)
  local entry = Mail.get(save, 3)
  check("the author is the mon's OT", entry.author, "RANDY")
  check("and the OT's ID", entry.authorId, 518)
  check("an empty party takes nothing",
    Mail.give(newSave(0), "FLOWER_MAIL", "HI"), false)
  check("and a non-mail item takes nothing",
    Mail.give(newSave(1), "POTION", "HI"), false)
end

-- ------------------------------------------------------- the slot shifting

-- sPartyMail is keyed by SLOT, so RemoveMonFromPartyOrBox shifts every struct
-- behind the departing mon up one ("Mail time!").
do
  local save = newSave(3)
  Mail.set(save, 2, Mail.entry("SURF_MAIL", "TWO"))
  Mail.set(save, 3, Mail.entry("EON_MAIL", "THREE"))
  Mail.removeSlot(save, 1)
  check("the second letter moved to slot 1", Mail.get(save, 1).message, "TWO")
  check("the third to slot 2", Mail.get(save, 2).message, "THREE")
  check("and the old last slot is empty", Mail.get(save, 3), nil)

  -- SwitchPartyMons swaps the two structs through wSwitchMonBuffer.
  Mail.swapSlots(save, 1, 2)
  check("a swap carries the letters", Mail.get(save, 1).message, "THREE")
  check("both ways", Mail.get(save, 2).message, "TWO")
end

-- IsAnyMonHoldingMail is a whole-party question, which is what makes MOVE
-- POKéMON W/O MAIL an all-or-nothing refusal.
do
  local save = newSave(3)
  check("a clean party holds no mail", Mail.anyMonHoldingMail(save), false)
  save.party[3].item = "LITEBLUEMAIL"
  check("one letter anywhere is enough", Mail.anyMonHoldingMail(save), true)
  save.party[3].item = "POTION"
  check("an ordinary held item is not", Mail.anyMonHoldingMail(save), false)
end

-- ----------------------------------------------------------- the MAILBOX

do
  local save = newSave(2)
  save.party[1].item = "FLOWER_MAIL"
  Mail.compose(save, 1, "HELLO", save.party[1], "FLOWER_MAIL")
  check("the MAILBOX starts empty", Mail.mailboxCount(save), 0)
  check("SendMailToPC moves the letter", Mail.sendToPc(save, 1), true)
  check("the MAILBOX has it", Mail.mailboxCount(save), 1)
  check("the party slot is cleared", Mail.get(save, 1), nil)
  -- SendMailToPC writes the mon's held item byte to 0 in the same routine.
  check("and the mon is no longer holding it", save.party[1].item, nil)
  check("a mon with no mail sends nothing", Mail.sendToPc(save, 2), false)

  -- MAILBOX_CAPACITY is 10 and .full is carry, which MonMailAction prints
  -- _MailboxFullText for.
  for i = 2, Mail.MAILBOX_CAPACITY do
    Mail.mailbox(save)[i] = Mail.entry("SURF_MAIL", "N" .. i)
  end
  check("the MAILBOX fills at ten", Mail.mailboxFull(save), true)
  save.party[2].item = "EON_MAIL"
  Mail.compose(save, 2, "LATE", save.party[2], "EON_MAIL")
  check("and refuses an eleventh", Mail.sendToPc(save, 2), false)
  check("leaving the letter on the mon", Mail.get(save, 2).message, "LATE")

  -- DeleteMailFromPC keeps sMailboxes dense.
  local removed = Mail.deleteFromPc(save, 1)
  check("delete answers the letter", removed.message, "HELLO")
  check("and closes the list up", Mail.mailboxCount(save), 9)
  check("with the next one first", Mail.mailbox(save)[1].message, "N2")
  check("deleting nothing answers nil", Mail.deleteFromPc(save, 99), nil)
end

-- MoveMailFromPCToParty: the struct moves AND the mail's type byte becomes the
-- mon's held item, which is how the letter and its stationery stay together.
do
  local save = newSave(2)
  Mail.mailbox(save)[1] = Mail.entry("MUSIC_MAIL", "TUNE", "AMY", 7, "NATU")
  check("attach moves it", Mail.moveFromPcToParty(save, 1, 2), true)
  check("the mon holds the stationery", save.party[2].item, "MUSIC_MAIL")
  check("and carries the letter", Mail.get(save, 2).message, "TUNE")
  check("the MAILBOX is empty again", Mail.mailboxCount(save), 0)
  check("attaching from an empty box fails",
    Mail.moveFromPcToParty(save, 1, 1), false)
end

-- --------------------------------------------------------- CheckPokeMail

-- The order of these five is the cart's, and it is load bearing: the one call
-- site (Route31MailRecipientScript) has an `ifequal` for every value.
do
  local EXPECT = "DARK CAVE leads\nto another road"
  -- REFUSED: the B press, which never looks at a mon at all.
  check("no slot is REFUSED",
    Mail.checkPokeMail(newSave(2), nil, EXPECT), Mail.POKEMAIL_REFUSED)

  -- NO_MAIL beats WRONG_MAIL: ItemIsMail is asked before the bytes are.
  local plain = newSave(2)
  check("a mon with no mail is NO_MAIL",
    Mail.checkPokeMail(plain, 1, EXPECT), Mail.POKEMAIL_NO_MAIL)

  local wrong = newSave(2)
  wrong.party[1].item = "FLOWER_MAIL"
  Mail.compose(wrong, 1, "SOMETHING ELSE", wrong.party[1], "FLOWER_MAIL")
  check("the wrong letter is WRONG_MAIL",
    Mail.checkPokeMail(wrong, 1, EXPECT), Mail.POKEMAIL_WRONG_MAIL)

  -- LAST_MON is checked AFTER the message compares equal, so the right mon
  -- with the right letter still loses you the reward if it is all you have.
  local last = newSave(1)
  last.party[1].item = "FLOWER_MAIL"
  Mail.give(last, "FLOWER_MAIL", EXPECT)
  check("the last conscious mon is LAST_MON",
    Mail.checkPokeMail(last, 1, EXPECT), Mail.POKEMAIL_LAST_MON)
  check("and it is still in the party", #last.party, 1)

  local ok = newSave(2)
  Mail.give(ok, "FLOWER_MAIL", EXPECT)
  check("the right letter is CORRECT",
    Mail.checkPokeMail(ok, 2, EXPECT), Mail.POKEMAIL_CORRECT)
  check("and the mon is gone", #ok.party, 1)

  -- A stored message LONGER than the expected one still matches: the compare
  -- runs until the expected string's own '@'.
  local longer = newSave(2)
  Mail.give(longer, "FLOWER_MAIL", EXPECT .. "!")
  check("a longer stored message still matches",
    Mail.checkPokeMail(longer, 2, EXPECT), Mail.POKEMAIL_CORRECT)

  -- No expected message resolved (a cache built before the extractor followed
  -- the operand): the answer that changes nothing.
  local unresolved = newSave(2)
  Mail.give(unresolved, "FLOWER_MAIL", EXPECT)
  check("an unresolved expectation is WRONG_MAIL",
    Mail.checkPokeMail(unresolved, 2, nil), Mail.POKEMAIL_WRONG_MAIL)
  check("and keeps the mon", #unresolved.party, 2)

  -- CORRECT removes the mon, so the mail shift has to ride along with it.
  local shift = newSave(3)
  Mail.set(shift, 3, Mail.entry("SURF_MAIL", "BEHIND"))
  shift.party[1].item = "FLOWER_MAIL"
  Mail.compose(shift, 1, EXPECT, shift.party[1], "FLOWER_MAIL")
  check("handing over slot 1 is CORRECT",
    Mail.checkPokeMail(shift, 1, EXPECT), Mail.POKEMAIL_CORRECT)
  check("and the letter behind it moved up",
    Mail.get(shift, 2).message, "BEHIND")
end

-- ------------------------------------------------------------- refusals

-- BillsPC_CheckMon's .HasMail arm: DEPOSIT refuses, after the last-healthy
-- rule and before anything moves.
do
  local save = newSave(3)
  save.party[1].item = "PORTRAITMAIL"
  local ok, reason = Boxes.canDeposit(save, 1, 1)
  check("a mail holder cannot be deposited", ok, false)
  check("with PCString_RemoveMail", reason, "Remove MAIL.")
  check("deposit really refuses", (Boxes.deposit(save, 1, 1)), false)
  check("and the party is untouched", #save.party, 3)

  -- Depositing anything else still shifts the letters behind it.
  local shift = newSave(3)
  Mail.set(shift, 3, Mail.entry("SURF_MAIL", "THIRD"))
  check("an ordinary deposit works", (Boxes.deposit(shift, 2, 1)), true)
  check("and the letter moved up with its mon",
    Mail.get(shift, 2).message, "THIRD")
end

-- SelectTradeOrDayCareMon's ItemIsMail arm, which used to guess from the id's
-- spelling and so let LITEBLUEMAIL straight past.
do
  local save = newSave(3)
  save.party[1].item = "LITEBLUEMAIL"
  check("the Day-Care sees the mail",
    Breeding.holdsMail(nil, save.party[1]), true)
  local ok, reason = Breeding.canDeposit({}, save, "man", 1)
  check("and refuses the deposit", ok, false)
  check("with REFUSE_MAIL", reason, Breeding.REFUSE_MAIL)
end

-- ------------------------------------------------------------ save format

-- MAIL is the 3 -> 4 step.  The file has moved past 4 since (format 5 is the
-- world state), so what this suite ratchets is that the mail step is still
-- there and that a format-3 save still comes all the way up; the current
-- number itself is gen2_save_test's business.
check("mail is the 3 -> 4 step", type(Save.MIGRATIONS[3]), "function")
check("and the format has not gone backwards", Save.FORMAT >= 4, true)
for from = 1, Save.FORMAT - 1 do
  check("a migration exists for format " .. from,
    type(Save.MIGRATIONS[from]), "function")
end
do
  local old = Save.normalize(Save.migrate({ format = 3, party = {} }))
  check("a format-3 save reaches the current format", old.format, Save.FORMAT)
  check("and gains the party half", type(old.mail.party), "table")
  check("and the MAILBOX half", type(old.mail.box), "table")
  check("both empty", next(old.mail.party), nil)
end

-- The quarantine pass.  Every entry below is a region the cart could not have
-- written, so it is dropped and reported rather than handed to a screen.
do
  local dirty = Save.newGame({})
  dirty.mail = {
    party = {
      [1] = Mail.entry("FLOWER_MAIL", "FINE"),
      [7] = Mail.entry("SURF_MAIL", "OUT OF RANGE"),
      [2] = Mail.entry("POTION", "NOT MAIL"),
      [3] = { type = "EON_MAIL", message = ("Z"):rep(40) },
      [4] = "not a struct",
    },
    box = {
      Mail.entry("MUSIC_MAIL", "KEPT"),
      { type = "MASTER_BALL", message = "NOT MAIL" },
    },
  }
  local report = Save.validate(dirty)
  check("the good letter survives", Mail.get(dirty, 1).message, "FINE")
  check("the out-of-range slot is gone", Mail.get(dirty, 7), nil)
  check("the non-mail stationery is gone", Mail.get(dirty, 2), nil)
  check("the non-struct is gone", Mail.get(dirty, 4), nil)
  check("the over-long message is trimmed",
    #Mail.get(dirty, 3).message, Mail.MAIL_MSG_LENGTH)
  check("the good MAILBOX entry survives", Mail.mailbox(dirty)[1].message,
    "KEPT")
  check("the bad one is gone", Mail.mailbox(dirty)[2], nil)
  -- four drops: the slot, the item, the struct, and the MAILBOX row -- plus
  -- the trim, which is reported without losing the letter.
  check("five entries reported", #report.lostMail, 5)
  check("and the report is not empty", Save.emptyReport(report), false)
end
check("a fresh save reports nothing",
  Save.emptyReport(Save.validate(Save.newGame({}))), true)
-- A `mail` field that is not even a table is replaced wholesale.
do
  local wrecked = Save.newGame({})
  wrecked.mail = 7
  local report = Save.validate(wrecked)
  check("a non-table store is quarantined", #report.lostMail, 1)
  check("and replaced", type(wrecked.mail), "table")
end

-- -------------------------------------------------------------- screen ids

-- Every mail screen is reached through src/ui/Screens.lua, so a mod can
-- replace one.
Screens.invalidate()
for _, pair in ipairs({
  { "Gen2MailCompose", MailCompose },
  { "Gen2MailRead", MailRead },
  { "Gen2MailMenu", MailMenu },
  { "Gen2MailboxMenu", MailboxMenu },
  { "Gen2HeldItemMenu", HeldItemMenu },
}) do
  check(pair[1] .. " resolves to its builtin",
    Screens.get({ data = {} }, pair[1]), pair[2])
end

-- ----------------------------------------------------------- the keyboard

-- data/text/mail_input_chars.asm: ten columns, six rows, and the fifth row of
-- each case is the one that is NOT a plain letter grid.
do
  local save = newSave(1)
  local game, input = newGame(save)
  local composed = nil
  local screen = MailCompose.new(game, {
    onDone = function(text) composed = text end,
  })
  check("the upper grid has five letter rows", #MailCompose.MAIL_INPUT_UPPER, 5)
  check("ten columns", #MailCompose.MAIL_INPUT_UPPER[1], 10)
  check("row 1 starts at A", MailCompose.MAIL_INPUT_UPPER[1][1], "A")
  check("and ends at J", MailCompose.MAIL_INPUT_UPPER[1][10], "J")
  check("row 4 is the digits", MailCompose.MAIL_INPUT_UPPER[4][10], "0")
  check("row 5 opens on <PK>", MailCompose.MAIL_INPUT_UPPER[5][1], "<PK>")
  check("and the lower row 4 on the apostrophe pairs",
    MailCompose.MAIL_INPUT_LOWER[4][1], "'d")

  -- The cursor starts on A.
  check("the cursor starts on A", screen:cursorCharacter(), "A")
  input:press("a")
  screen:update()
  check("A types it", screen.text, "A")

  -- .right wraps at column 9, not 8: the mail grid is one wider than the
  -- naming screen's.
  screen.col, screen.row = 9, 0
  screen:moveHorizontal(1)
  check("right wraps from column 9", screen.col, 0)
  screen:moveHorizontal(-1)
  check("and left wraps back to 9", screen.col, 9)

  -- SELECT is the case switch anywhere.
  input:press("select")
  screen:update()
  check("select switches case", screen.lower, true)
  screen.col, screen.row = 0, 0
  check("the lower grid is under it", screen:cursorCharacter(), "a")

  -- START parks the cursor on END; A there finishes.
  input:press("start")
  screen:update()
  check("start lands on the strip", screen.row, 5)
  check("over END", screen:cursorCharacter(), "END")
  input:press("a")
  screen:update()
  check("END hands the message back", composed, "A")

  -- The three fat targets split at 0-2 / 3-5 / 6-9.
  screen.row, screen.col = 5, 0
  check("column 0 is the case switch", screen:cursorCharacter(), "CASE")
  screen.col = 3
  check("column 3 is DEL", screen:cursorCharacter(), "DEL")
  screen.col = 6
  check("column 6 is END", screen:cursorCharacter(), "END")
  -- and right from END wraps to the case switch rather than stepping.
  screen:moveHorizontal(1)
  check("right from END wraps", screen:cursorCharacter(), "CASE")

  -- B deletes rather than cancelling: there is no way out but END.
  screen.text = "AB"
  input:press("b")
  screen:update()
  check("B deletes a character", screen.text, "A")

  -- The buffer is 32 characters and the last one does NOT end entry the way a
  -- nickname's does.
  screen.text = ("Q"):rep(Mail.MAIL_MSG_LENGTH)
  screen.row, screen.col = 0, 0
  composed = nil
  input:press("a")
  screen:update()
  check("a full message takes nothing more",
    #screen.text, Mail.MAIL_MSG_LENGTH)
  check("and does not finish on its own", composed, nil)
end

-- ------------------------------------------------------------ MonMailAction

-- The MAIL row only appears when ItemIsMail says so.
do
  local save = newSave(1)
  local game = newGame(save)
  local list = PartyMenu.new(game, { save = save })
  local rows = list:submenuItems(save.party[1])
  local labels = {}
  for _, row in ipairs(rows) do labels[row.id] = true end
  check("a mon with nothing shows ITEM", labels.ITEM, true)
  check("and no MAIL row", labels.MAIL, nil)

  save.party[1].item = "PORTRAITMAIL"
  local mailRows = list:submenuItems(save.party[1])
  local mailLabels = {}
  for _, row in ipairs(mailRows) do mailLabels[row.id] = true end
  check("a mail holder shows MAIL", mailLabels.MAIL, true)
  check("and no ITEM row", mailLabels.ITEM, nil)
end

-- TAKE, both endings.
do
  local save = newSave(2)
  save.party[1].item = "FLOWER_MAIL"
  Mail.compose(save, 1, "KEEPSAKE", save.party[1], "FLOWER_MAIL")
  local game, input = newGame(save)
  local closed = false
  local menu = MailMenu.new(game, {
    save = save, slot = 1, onClose = function() closed = true end,
  })
  check("the menu is READ / TAKE / QUIT", #MailMenu.ENTRIES, 3)
  -- Down to TAKE, then A: the first question is the PC one.
  input:press("down")
  menu:update()
  check("the cursor is on TAKE", MailMenu.ENTRIES[menu.index].id, "take")
  input:press("a")
  menu:update()
  check("TAKE asks about the PC first", menu.confirm ~= nil, true)
  -- YES: SendMailToPC.
  input:press("a")
  menu:update()
  check("the letter went to the PC", Mail.mailboxCount(save), 1)
  check("and off the mon", save.party[1].item, nil)
  check("with a line to read", menu.message ~= nil, true)
  input:press("a")
  menu:update()
  check("which closes the menu", closed, true)
end

do
  -- Saying no to the PC drops into "the MAIL will lose its message".
  local save = newSave(2)
  save.party[1].item = "SURF_MAIL"
  Mail.compose(save, 1, "BYE", save.party[1], "SURF_MAIL")
  local game, input = newGame(save)
  local menu = MailMenu.new(game, { save = save, slot = 1, onClose = function() end })
  menu.index = 2
  input:press("a")
  menu:update()
  -- NO to the PC question.
  input:press("down")
  menu:update()
  input:press("a")
  menu:update()
  check("saying no asks the destructive question", menu.confirm ~= nil, true)
  -- YES to losing the message.
  input:press("a")
  menu:update()
  check("the stationery is in the bag", save.inventory.SURF_MAIL, 1)
  check("the mon is empty handed", save.party[1].item, nil)
  check("and the letter is gone", Mail.get(save, 1), nil)
end

do
  -- A full bag is _MailNoSpaceText, and the letter survives it.
  local save = newSave(2)
  save.party[1].item = "EON_MAIL"
  Mail.compose(save, 1, "STAYS", save.party[1], "EON_MAIL")
  for i = 1, 20 do save.inventory["FILLER_" .. i] = 1 end
  local game, input = newGame(save)
  local menu = MailMenu.new(game, { save = save, slot = 1, onClose = function() end })
  menu.index = 2
  input:press("a")
  menu:update()
  input:press("down")
  menu:update()
  input:press("a")
  menu:update()
  input:press("a")
  menu:update()
  check("a full PACK keeps the letter", Mail.get(save, 1).message, "STAYS")
  check("and the mon keeps holding it", save.party[1].item, "EON_MAIL")
end

-- ------------------------------------------------------------- MailboxPC

-- InitMail's z branch: an empty MAILBOX never opens a menu.
do
  local save = newSave(1)
  local game, input = newGame(save)
  local closed = false
  local box = MailboxMenu.new(game, {
    save = save, onClose = function() closed = true end,
  })
  check("an empty MAILBOX opens on a line", box.message ~= nil, true)
  input:press("a")
  box:update()
  check("and closes", closed, true)
end

do
  local save = newSave(2)
  Mail.mailbox(save)[1] = Mail.entry("FLOWER_MAIL", "ONE", "AMY", 1, "ODDISH")
  Mail.mailbox(save)[2] = Mail.entry("SURF_MAIL", "TWO", "BEN", 2, "LAPRAS")
  local game, input = newGame(save)
  local box = MailboxMenu.new(game, { save = save, onClose = function() end })
  check("the list opens on the first letter", box.index, 1)
  check("with four submenu rows", #MailboxMenu.SUB_ENTRIES, 4)
  input:press("a")
  box:update()
  check("A opens the submenu", box.submenu ~= nil, true)
  check("on READ MAIL", MailboxMenu.SUB_ENTRIES[box.submenu.index].id, "read")

  -- PUT IN PACK: the question, then the stationery.
  box.submenu.index = 2
  input:press("a")
  box:update()
  check("PUT IN PACK asks first", box.confirm ~= nil, true)
  input:press("a")
  box:update()
  check("the stationery is in the bag", save.inventory.FLOWER_MAIL, 1)
  check("and the letter is gone", Mail.mailboxCount(save), 1)
  check("with the next one first", Mail.mailbox(save)[1].message, "TWO")
end

do
  -- ATTACH MAIL refuses a mon that is already holding something, and comes
  -- straight back to the party list rather than backing out.
  local save = newSave(2)
  save.party[1].item = "POTION"
  Mail.mailbox(save)[1] = Mail.entry("LOVELY_MAIL", "XOXO", "AMY", 1)
  local game, input = newGame(save)
  local box = MailboxMenu.new(game, { save = save, onClose = function() end })
  box.submenu = { index = 3 }
  input:press("a")
  box:update()
  local list = game.stack:top()
  check("the party list is up", list ~= nil, true)
  list.onChoose(1, save.party[1])
  check("a mon holding an item is refused", box.message ~= nil, true)
  check("and the letter is still in the MAILBOX", Mail.mailboxCount(save), 1)

  -- An empty-handed mon takes it.
  input:press("a")
  box:update()
  local retry = game.stack:top()
  retry.onChoose(2, save.party[2])
  check("an empty-handed mon takes it", save.party[2].item, "LOVELY_MAIL")
  check("with the letter", Mail.get(save, 2).message, "XOXO")
  check("out of the MAILBOX", Mail.mailboxCount(save), 0)
end

-- ------------------------------------------------------------ the PC menu

-- MAIL BOX is on both .WhichPC lists, so it is on the storage menu this port
-- folds them into whichever PC opened it.
do
  local ids = {}
  for _, entry in ipairs(PcMenu.ENTRIES) do ids[entry.id] = true end
  check("the PC has a MAIL BOX row", ids.mailbox, true)
end

-- BillsPC_MovePKMNMenu asks IsAnyMonHoldingMail before it opens anything.
do
  local save = newSave(2)
  save.party[2].item = "MORPH_MAIL"
  local game, input = newGame(save)
  local pc = PcMenu.new(game, { save = save, onClose = function() end })
  for i, entry in ipairs(pc.entries) do
    if entry.id == "move" then pc.index = i end
  end
  pc:choose()
  check("MOVE refuses while a letter is in the party", pc.message ~= nil, true)
  check("without opening a list", #game.stack._items, 0)
  -- The refusal is two pages and neither of them logs off.
  input:press("a")
  pc:update()
  check("the second page follows", pc.message ~= nil, true)
  input:press("a")
  pc:update()
  check("and then the menu is back", pc.message, nil)

  -- With the letter gone the row opens the list as usual.
  save.party[2].item = nil
  pc:choose()
  check("MOVE opens the list once the mail is off",
    #game.stack._items, 1)
end

-- ------------------------------------------------- GiveTakePartyMonItem
--
-- The ITEM row is what makes MAIL reachable at all: GivePartyItem ->
-- ComposeMailMessage is the compose keyboard's only door on the cart.

local ITEMS = {
  FLOWER_MAIL = { id = "FLOWER_MAIL", name = "FLOWER MAIL", pocket = "ITEM" },
  POTION = { id = "POTION", name = "POTION", pocket = "ITEM" },
  BERRY = { id = "BERRY", name = "BERRY", pocket = "ITEM" },
  BICYCLE = { id = "BICYCLE", name = "BICYCLE", pocket = "KEY_ITEM" },
}

do
  -- Giving MAIL to an empty-handed mon opens the keyboard, and END writes the
  -- struct on that mon's party slot.
  local save = newSave(2)
  save.inventory.FLOWER_MAIL = 1
  local game, input = newGame(save)
  game.data.items = ITEMS
  local closed = false
  local menu = HeldItemMenu.new(game, {
    save = save, slot = 1, items = ITEMS,
    onClose = function() closed = true end,
  })
  check("the menu is GIVE / TAKE", #HeldItemMenu.ENTRIES, 2)
  input:press("a")
  menu:update()
  local pack = game.stack:top()
  check("GIVE opens the PACK", pack ~= nil, true)
  check("as a chooser", pack.give, true)
  pack.onChoose("FLOWER_MAIL")
  check("the mon is holding it", save.party[1].item, "FLOWER_MAIL")
  check("and it left the bag", save.inventory.FLOWER_MAIL, nil)
  check("with a line to read", menu.message ~= nil, true)
  typeOut(menu)
  input:press("a")
  menu:update()
  local compose = game.stack:top()
  check("the compose keyboard is up", compose ~= nil, true)
  compose.onDone("SEE YOU SOON")
  check("the letter is on the slot", Mail.get(save, 1).message, "SEE YOU SOON")
  check("with the player as author", Mail.get(save, 1).author, "GOLD")
  check("and the menu closed", closed, true)
end

do
  -- A mon already holding MAIL is refused BEFORE the swap question, so a
  -- letter cannot be knocked off by accident.
  local save = newSave(1)
  save.party[1].item = "FLOWER_MAIL"
  Mail.compose(save, 1, "SAFE", save.party[1], "FLOWER_MAIL")
  save.inventory.POTION = 1
  local game = newGame(save)
  game.data.items = ITEMS
  local menu = HeldItemMenu.new(game, {
    save = save, slot = 1, items = ITEMS, onClose = function() end,
  })
  menu:giveItem("POTION")
  check("a mail holder refuses a new item", menu.message ~= nil, true)
  check("and keeps the letter", Mail.get(save, 1).message, "SAFE")
  check("and the stationery", save.party[1].item, "FLOWER_MAIL")
  check("with the POTION still in the bag", save.inventory.POTION, 1)
end

do
  -- .next: a KEY_ITEM cannot be held, and the PACK comes back rather than the
  -- menu closing.
  local save = newSave(1)
  save.inventory.BICYCLE = 1
  local game, input = newGame(save)
  game.data.items = ITEMS
  local closed = false
  local menu = HeldItemMenu.new(game, {
    save = save, slot = 1, items = ITEMS,
    onClose = function() closed = true end,
  })
  menu:giveItem("BICYCLE")
  check("a key item cannot be held", menu.message ~= nil, true)
  check("and the mon holds nothing", save.party[1].item, nil)
  typeOut(menu)
  input:press("a")
  menu:update()
  check("the PACK reopens", game.stack:top() ~= nil, true)
  check("rather than the menu closing", closed, false)
end

do
  -- TAKE puts the item back in the bag.
  local save = newSave(1)
  save.party[1].item = "BERRY"
  local game, input = newGame(save)
  game.data.items = ITEMS
  local menu = HeldItemMenu.new(game, {
    save = save, slot = 1, items = ITEMS, onClose = function() end,
  })
  input:press("down")
  menu:update()
  check("the cursor is on TAKE", HeldItemMenu.ENTRIES[menu.index].id, "take")
  input:press("a")
  menu:update()
  check("the item is back in the bag", save.inventory.BERRY, 1)
  check("and off the mon", save.party[1].item, nil)

  -- An empty-handed mon is _PokemonNotHoldingText and nothing moves.
  local bare = newSave(1)
  local bareGame = newGame(bare)
  bareGame.data.items = ITEMS
  local bareMenu = HeldItemMenu.new(bareGame, {
    save = bare, slot = 1, items = ITEMS, onClose = function() end,
  })
  bareMenu:takeItem()
  check("an empty-handed mon says so", bareMenu.message ~= nil, true)
  check("and gains nothing", next(bare.inventory), nil)
end

do
  -- The swap question, and the bag-full arm that puts the old item straight
  -- back rather than destroying either one.
  local save = newSave(1)
  save.party[1].item = "BERRY"
  -- Two POTIONs so the slot survives GiveItemToPokemon's own remove; with one
  -- the freed slot is exactly the room the BERRY needs and the swap succeeds,
  -- which is the cart's behaviour too.
  save.inventory.POTION = 2
  for i = 1, 19 do save.inventory["FILLER_" .. i] = 1 end
  local game, input = newGame(save)
  game.data.items = ITEMS
  local menu = HeldItemMenu.new(game, {
    save = save, slot = 1, items = ITEMS, onClose = function() end,
  })
  menu:giveItem("POTION")
  check("a held item asks about the swap", menu.confirm ~= nil, true)
  typeOut(menu)
  input:press("a")
  menu:update()
  typeOut(menu)
  input:press("a")
  menu:update()
  check("a full bag keeps the old item on the mon", save.party[1].item, "BERRY")
  check("and puts the new one back", save.inventory.POTION, 2)
  check("with the storage-full line up", menu.message ~= nil, true)
end

do
  -- ...and with room, the swap goes through both ways.
  local save = newSave(1)
  save.party[1].item = "BERRY"
  save.inventory.POTION = 1
  local game, input = newGame(save)
  game.data.items = ITEMS
  local menu = HeldItemMenu.new(game, {
    save = save, slot = 1, items = ITEMS, onClose = function() end,
  })
  menu:giveItem("POTION")
  -- _PokemonAskSwapItemText has a `para` in it, so the box turns a page before
  -- the YES/NO comes up.
  typeOut(menu)
  input:press("a")
  menu:update()
  typeOut(menu)
  input:press("a")
  menu:update()
  check("the mon holds the new item", save.party[1].item, "POTION")
  check("and the old one is in the bag", save.inventory.BERRY, 1)
  check("with the new one gone from it", save.inventory.POTION, nil)
end

-- -------------------------------------------------------------- MailRead

-- MailGFX_PlaceMessage's three author columns, picked by the stationery.
do
  local game = newGame(newSave(1))
  local read = MailRead.new(game, {
    entry = Mail.entry("PORTRAITMAIL", "HI", "AMY", 1),
  })
  check("PORTRAITMAIL puts the author at 8", read:authorColumn(), 8)
  read.entry = Mail.entry("MORPH_MAIL", "HI", "AMY", 1)
  check("MORPH_MAIL at 6", read:authorColumn(), 6)
  read.entry = Mail.entry("FLOWER_MAIL", "HI", "AMY", 1)
  check("everything else at 5", read:authorColumn(), 5)
end

print(("gen2 mail: %d checks, %d failures"):format(checks, failures))
if failures > 0 then os.exit(1) end
