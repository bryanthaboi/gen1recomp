-- The Day-Care conversation: deposit, withdraw, and the egg handover outside
-- (engine/events/daycare.asm DayCareMan / DayCareLady / DayCareManOutside).
--
-- There is no menu of the Day-Care's own on the cart.  All three routines are
-- PrintDayCareText + YesNoBox + SelectTradeOrDayCareMon, so this screen is a
-- speech box, a yes/no box and a push of the party list -- which is why it
-- reads as a phase machine rather than as a list with a cursor, and why every
-- coordinate below is one of the shared ones:
--
-- THIS SCREEN DRAWS OVER THE LIVE MAP AND MUST NEVER CLEAR THE FIELD.  Both
-- NPC scripts are `faceplayer / opentext / special DayCareMan / waitbutton /
-- closetext` (maps/DayCare.asm DayCareManScript_Inside, DayCareLadyScript),
-- and nothing the special reaches -- DayCareMan, DayCareLady, PrintDayCareText
-- or YesNoBox -- blanks the screen, so the Day-Care room stays visible behind
-- the textbox exactly the way any other `opentext` conversation does.  Hence
-- isOpaque = false (StateStack keeps the overworld in the frame), no
-- drawsWidescreen/drawWidescreen (Game2:drawScene must fall through to
-- world:draw + stack:drawCanvas at the plain integer letterbox fit) and no
-- Chrome.clear in drawPanel: Chrome.box paints an opaque box on its own.  This
-- is the same shape every screen that overlays the map uses (BankOfMom,
-- ScriptMenu, ElevatorMenu, MailMenu, StartMenu).
--
--   Textbox        `lb bc, 4, 18` at (0,12) -- a 20x6 box.  TEXTBOX_INNERY is
--                  TEXTBOX_Y + 2 and LineChar targets INNERY + 2, so the two
--                  lines are at rows 14 and 16, TWO apart.
--   YesNoBox       `lb bc, SCREEN_WIDTH - 6, 7` -- a 6x5 box at (14,7).
--                  YesNoMenuHeader sets STATICMENU_CURSOR *and*
--                  STATICMENU_NO_TOP_SPACING, so GetMenuTextStartCoord puts
--                  YES at (16,8) and NO at (16,10) with the cursor column at
--                  15.
--   LoadBlinkingCursor  the ▼ at (18,17) while a page waits for a button.
--
-- The party list is opened through Screens ("Gen2PartyMenu") with
-- PARTYMENUACTION_GIVE_MON, whose PartyMenuStrings row is ChooseAMonString --
-- the plain "Choose a #MON." prompt, not one of the item-flavoured ones.
--
-- Every string is transcribed from data/text/common_1.asm's _DayCare* /
-- _Breed* block, and paired with its pokegold label in LABELS below.  No
-- script bytecode points at any of them -- PrintDayCareText is asm -- so the
-- extractor seeds its text walker at the block by name (RomExtractorGen2's
-- NAMED_TEXT) and the screen prefers the cache's own characters, falling back
-- to the transcription for a cache built before that seed.
--
-- The MODEL is src/core/gen2/Breeding.lua -- every refusal, price, deposit and
-- egg roll below is one call into it, so the conversation can be wrong about
-- its layout without ever being wrong about the rules.

local Breeding = require("src.core.gen2.Breeding")
local Chrome = require("src.ui.gen2.Chrome")
local CommonText = require("src.core.gen2.CommonText")
local Screens = require("src.ui.Screens")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Typer = require("src.ui.gen2.Typer")

local DayCareMenu = {}
DayCareMenu.__index = DayCareMenu
DayCareMenu.isOpaque = false

-- charmap.asm's currency glyph and the text-advance arrow (font code $ee),
-- spelled the same way MartMenu spells them so both go through Font.split's
-- charmap match rather than through four ASCII tiles.
local YEN = "\xc2\xa5"
local DOWN_ARROW = "\xe2\x96\xbc"

-- ---------------------------------------------------------------- layout
local TEXT_BOX_X, TEXT_BOX_Y, TEXT_BOX_W, TEXT_BOX_H = 0, 12, 20, 6
local TEXT_X, TEXT_Y, TEXT_LINE = 1, 14, 2
local ARROW_X, ARROW_Y = 18, 17

local YESNO_X, YESNO_Y, YESNO_W, YESNO_H = 14, 7, 6, 5

-- ------------------------------------------------------------------ sfx
--
-- Named the pokegold way; Sound.GEN2_ALIASES is what maps the shared UI's own
-- labels onto these.  SFX_TRANSACTION rings in RetrieveMonFromDayCareMan
-- BEFORE the money is taken (it is the mon coming back, not the payment), and
-- SFX_GET_EGG in DayCareManOutside right after the egg lands in the party.
local SFX_TRANSACTION = "Sfx_Transaction"
local SFX_GET_EGG = "Sfx_GetEgg"

-- `ld c, 120 / call DelayFrames` between _ReceivedEggText and
-- _TakeGoodCareOfEggText: two full seconds of the jingle before he speaks
-- again.
local GET_EGG_FRAMES = 120

-- ----------------------------------------------------------------- text
--
-- A "page" is one screenful: up to two lines, TEXT_LINE rows apart.  A `para`
-- in the ASM starts a new page; a `cont` scrolls one line, which shows as a
-- page whose first line is the previous page's second.
local function page(...) return { ... } end
local function pages(...) return { ... } end

local TEXT = {
  -- _DayCareManIntroText / _DayCareManIntroEggText.  The "_EGG" one is the
  -- LONGER first-meeting script -- DayCareIntroText's `inc a` picks it the one
  -- time DAYCARE_INTRO_SEEN_F is clear, so it explains what eggs are rather
  -- than announcing that you have one.
  manIntro = pages(
    page("I'm the DAY-CARE", "MAN. Want me to"),
    page("MAN. Want me to", "raise a #MON?")),
  manIntroEgg = pages(
    page("I'm the DAY-CARE", "MAN. Do you know"),
    page("MAN. Do you know", "about EGGS?"),
    page("I was raising", "#MON with my"),
    page("#MON with my", "wife, you see."),
    page("We were shocked to", "find an EGG!"),
    page("How incredible is", "that?"),
    page("So, want me to", "raise a #MON?")),
  ladyIntro = pages(
    page("I'm the DAY-CARE", "LADY."),
    page("Should I raise a", "#MON for you?")),
  ladyIntroEgg = pages(
    page("I'm the DAY-CARE", "LADY. Do you know"),
    page("LADY. Do you know", "about EGGS?"),
    page("My husband and I", "were raising some"),
    page("were raising some", "#MON, you see."),
    page("We were shocked to", "find an EGG!"),
    page("How incredible", "could that be?"),
    page("Should I raise a", "#MON for you?")),

  -- DAYCARETEXT_WHICH_ONE, a `prompt`: it waits for a button and only then
  -- does SelectTradeOrDayCareMon open the party list over it.
  whichOne = pages(page("What should I", "raise for you?")),

  -- DayCareAskDepositPokemon's refusals, keyed by the Breeding.REFUSE_* the
  -- model hands back.
  lastMon = pages(page("Oh? But you have", "just one #MON.")),
  cantAcceptEgg = pages(page("Sorry, but I can't", "accept an EGG.")),
  removeMail = pages(page("Remove MAIL before", "you come see me.")),
  lastAliveMon = pages(
    page("If you give me", "that, what will"),
    page("that, what will", "you battle with?")),
  partyFull = pages(page("You have no room", "for it.")),
  notEnoughMoney = pages(page("You don't have", "enough money.")),
  ohFine = pages(page("Oh, fine then.")),
  comeAgain = pages(page("Come again.")),
  comeBackLater = pages(page("Come back for it", "later.")),

  -- _IllRaiseYourMonText: the nickname is a text_ram field, so it is spliced
  -- rather than being part of the string.
  deposit = function(name)
    return pages(page("OK. I'll raise", ("your %s."):format(name)))
  end,
  geniuses = function(name)
    return pages(
      page("Are we geniuses or", "what? Want to see"),
      page("what? Want to see", ("your %s?"):format(name)))
  end,
  -- _YourMonHasGrownText: `text_decimal wStringBuffer2 + 1, 1, 3` is the
  -- levels grown as a 3-wide left-aligned field, and
  -- `text_decimal wStringBuffer2 + 2, 3, 4` the price as a 4-wide one -- both
  -- LEFTALIGN, so neither is space padded.
  hasGrown = function(name, grown, price)
    return pages(
      page(("Your %s"):format(name), "has grown a lot."),
      page("By level, it's", ("grown by %d."):format(grown)),
      page("If you want your", "#MON back, it"),
      page("#MON back, it", ("will cost %s%d."):format(YEN, price)))
  end,
  -- _BackAlreadyText, the "grew nothing" branch.  Its price is a LITERAL
  -- ¥100 in the string, not a decimal field, which is the same number
  -- GetPriceToRetrieveBreedmon computes for zero levels grown.
  backAlready = function(name)
    return pages(
      page("Huh? Back already?", ("Your %s"):format(name)),
      page("needs a little", "more time with us."),
      page("If you want your", "#MON back, it"),
      page("#MON back, it", ("will cost %s100."):format(YEN)))
  end,
  withdraw = pages(page("Perfect! Here's", "your #MON.")),
  gotBack = function(player, name)
    return pages(page(("%s got back"):format(player), ("%s."):format(name)))
  end,

  -- DayCareManOutside.
  notYet = pages(page("Not yet…")),
  foundAnEgg = pages(
    page("Ah, it's you!"),
    page("We were raising", "your #MON, and"),
    page("my goodness, were", "we surprised!"),
    page("Your #MON had", "an EGG!"),
    page("We don't know how", "it got there, but"),
    page("your #MON had", "it. You want it?")),
  receivedEgg = function(player)
    return pages(page(("%s received"):format(player), "the EGG!"))
  end,
  takeGoodCare = pages(page("Take good care of", "it.")),
  illKeepIt = pages(page("Well then, I'll", "keep it. Thanks!")),
  noRoomForEgg = pages(
    page("You have no room", "in your party."),
    page("in your party.", "Come back later.")),
}

DayCareMenu.TEXT = TEXT

-- ...and the data/text/common_1.asm label each of those entries transcribes.
-- The extractor seeds its text walker at this whole block now
-- (RomExtractorGen2's NAMED_TEXT), so the cache carries the cart's own
-- characters and `self.TEXT` below prefers them; the transcription above is
-- what a cache built before that seed falls back to.
local LABELS = {
  manIntro = "_DayCareManIntroText",
  manIntroEgg = "_DayCareManIntroEggText",
  ladyIntro = "_DayCareLadyIntroText",
  ladyIntroEgg = "_DayCareLadyIntroEggText",
  whichOne = "_WhatShouldIRaiseText",
  lastMon = "_OnlyOneMonText",
  cantAcceptEgg = "_CantAcceptEggText",
  removeMail = "_RemoveMailText",
  lastAliveMon = "_LastHealthyMonText",
  partyFull = "_HaveNoRoomText",
  notEnoughMoney = "_NotEnoughMoneyText",
  ohFine = "_OhFineThenText",
  comeAgain = "_ComeAgainText",
  comeBackLater = "_ComeBackLaterText",
  deposit = "_IllRaiseYourMonText",
  geniuses = "_AreWeGeniusesText",
  hasGrown = "_YourMonHasGrownText",
  backAlready = "_BackAlreadyText",
  withdraw = "_PerfectHeresYourMonText",
  gotBack = "_GotBackMonText",
  notYet = "_NotYetText",
  foundAnEgg = "_FoundAnEggText",
  receivedEgg = "_ReceivedEggText",
  takeGoodCare = "_TakeGoodCareOfEggText",
  illKeepIt = "_IllKeepItThanksText",
  noRoomForEgg = "_NoRoomForEggText",
}

DayCareMenu.LABELS = LABELS

-- The six entries that take arguments hand them to CommonText.fill in the
-- order their string names its markers -- the text_ram nickname, then the
-- levels grown, then the price -- so each formatted entry keeps the signature
-- its transcription above already has.
local FILL = {
  deposit = function(name) return { name } end,
  geniuses = function(name) return { name } end,
  hasGrown = function(name, grown, price) return { name, grown, price } end,
  backAlready = function(name) return { name } end,
  gotBack = function(player, name) return { name, player = player } end,
  receivedEgg = function(player) return { player = player } end,
}

-- TEXT with every entry the cache carries replaced by the extracted string.
-- Anything the cache is missing falls through the metatable to the
-- transcription, so a partial cache is a mix rather than a hole.
local function extractedText(text)
  local out = setmetatable({}, { __index = TEXT })
  for key, label in pairs(LABELS) do
    local list = CommonText.of(text, label)
    if list then
      local fill = FILL[key]
      if fill then
        out[key] = function(...) return CommonText.fill(list, fill(...)) end
      else
        out[key] = list
      end
    end
  end
  return out
end

function DayCareMenu:wantsFillScale() return true end

-- The nickname the text_ram fields splice in: a nicknamed mon by its
-- nickname, anything else by its species name.
local function monName(mon)
  if not mon then return "#MON" end
  return mon.nickname or mon.name or mon.species or "#MON"
end

-- opts: save, side ("man" | "lady" | "outside"), text (text.lua, for the
-- extracted strings), onClose(scriptVar)
function DayCareMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, DayCareMenu)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.data = (game and game.data) or {}
  -- text.lua rides on the world, the way the Pokegear's phone strings do:
  -- this screen is pushed over the overworld and never without one.
  self.textData = opts.text or (game and game.world and game.world.text)
  self.TEXT = extractedText(self.textData)
  self.side = opts.side or "man"
  self.onClose = opts.onClose
  self.rng = opts.rng
  -- wScriptVar: DayCareManOutside is the only branch that writes one, and TRUE
  -- means "no room, ask again".
  self.scriptVar = 0
  self.delay = 0

  if self.side == "outside" then
    self:startOutside()
  elseif (Breeding.side(self.save, self.side) or {}).mon then
    self:startWithdraw()
  else
    self:startIntro()
  end
  return self
end

-- --------------------------------------------------------------- overlays
--
-- `say` is PrintText plus the button wait every one of these strings ends on
-- (`prompt` and `done` both park until A or B here, because the script that
-- calls the special does `waitbutton` straight after).
function DayCareMenu:say(list, onDone)
  -- ../pokecrystal/engine/events/daycare.asm:262 PrintDayCareText
  Typer.say(self, list, onDone)
end

function DayCareMenu:ask(list, onYes, onNo)
  self.confirm = { pages = list or {}, page = 1, choice = 1,
    onYes = onYes, onNo = onNo }
  Typer.begin(self, self.confirm)
end

function DayCareMenu:close()
  if self.onClose then self.onClose(self.scriptVar) end
end

-- `.print_text` then `.cancel`: the refusal, and then COME_AGAIN.
function DayCareMenu:refuse(key)
  local list = self.TEXT[key] or self.TEXT.ohFine
  self:say(list, function() self:comeAgain() end)
end

function DayCareMenu:comeAgain()
  self:say(self.TEXT.comeAgain, function() self:close() end)
end

function DayCareMenu:playSfx(name)
  local sfx = self.data.audio and self.data.audio.sfx
  if sfx and sfx[Sound.resolve(self.data, name)] then
    Sound.play(self.data, name)
  end
end

-- PlayMonCry, which is silent for a species with no extracted cry rather than
-- raising.
function DayCareMenu:playCry(species)
  if not species then return end
  local cries = self.data.audio and self.data.audio.cries
  if cries and cries[species] then Sound.playCry(self.data, species) end
end

-- ----------------------------------------------------------------- intro
--
-- DayCareIntroText: test DAYCARE_INTRO_SEEN_F, set it, and `inc a` to the
-- longer script the one time it was clear.  Declining goes straight to
-- `.cancel` -- COME_AGAIN with no "Oh, fine then." in front of it, which is
-- the difference between saying no here and cancelling the party list.
function DayCareMenu:startIntro()
  local first = Breeding.takeIntro(self.save, self.side)
  local lady = self.side == "lady"
  local list
  if lady then
    list = first and self.TEXT.ladyIntroEgg or self.TEXT.ladyIntro
  else
    list = first and self.TEXT.manIntroEgg or self.TEXT.manIntro
  end
  self:ask(list, function() self:askDeposit() end,
    function() self:comeAgain() end)
end

function DayCareMenu:askDeposit()
  local ok, reason = Breeding.canOpenDeposit(self.save)
  if not ok then return self:refuse(reason) end
  self:say(self.TEXT.whichOne, function() self:openParty() end)
end

function DayCareMenu:openParty()
  local game = self.game
  -- No stack means no party list to open; back out the way cancelling it does
  -- rather than pretending a mon was handed over.
  if not (game and game.stack) then return self:comeAgain() end
  self.picking = true
  Screens.push(game, "Gen2PartyMenu", {
    party = self.save.party,
    -- PARTYMENUACTION_GIVE_MON's PartyMenuStrings row is ChooseAMonString.
    prompt = "choose",
    onChoose = function(index)
      game.stack:pop()
      self.picking = false
      self:chose(index)
    end,
    onCancel = function()
      game.stack:pop()
      self.picking = false
      -- .Declined
      self:refuse("ohFine")
    end,
  })
end

function DayCareMenu:chose(index)
  local ok, reason = Breeding.canDeposit(self.data, self.save, self.side, index)
  if not ok then return self:refuse(reason) end
  local _, mon = Breeding.deposit(self.data, self.save, self.side, index,
    { rng = self.rng })
  -- DayCare_DepositPokemonText: the line, the cry, and then COME_BACK_LATER.
  -- The deposit path `ret`s rather than falling into `.cancel`, so there is
  -- deliberately no COME_AGAIN after it.
  self:say(self.TEXT.deposit(monName(mon)), function()
    self:playCry(mon and mon.species)
    self:say(self.TEXT.comeBackLater, function() self:close() end)
  end)
end

-- -------------------------------------------------------------- withdraw
--
-- DayCare_AskWithdrawBreedMon: no growth is ONE yes/no over _BackAlreadyText;
-- any growth is TWO, "Are we geniuses" and then the price.
function DayCareMenu:startWithdraw()
  local slot = Breeding.side(self.save, self.side)
  local _, _, grown = Breeding.levelGrowth(self.data, slot)
  local price = Breeding.retrievePrice(grown)
  local name = monName(slot.mon)
  self.grown, self.price = grown, price
  local decline = function() self:refuse("ohFine") end
  if grown == 0 then
    self:ask(self.TEXT.backAlready(name), function() self:takeMon() end, decline)
    return
  end
  self:ask(self.TEXT.geniuses(name), function()
    self:ask(self.TEXT.hasGrown(name, grown, price),
      function() self:takeMon() end, decline)
  end, decline)
end

function DayCareMenu:takeMon()
  local ok, reason = Breeding.canWithdraw(self.data, self.save, self.side)
  if not ok then return self:refuse(reason) end
  -- RetrieveMonFromDayCareMan rings the till and waits for it BEFORE
  -- GetBreedMon1LevelGrowth; the money changes hands afterwards, in
  -- DayCare_GetBackMonForMoney.
  self:playSfx(SFX_TRANSACTION)
  local _, mon = Breeding.withdraw(self.data, self.save, self.side)
  local player = (self.save.player and self.save.player.name) or "<PLAYER>"
  self:say(self.TEXT.withdraw, function()
    self:playCry(mon and mon.species)
    self:say(self.TEXT.gotBack(player, monName(mon)), function()
      self:comeAgain()
    end)
  end)
end

-- --------------------------------------------------------------- outside
--
-- DayCareManOutside.  The party-space check happens AFTER the yes, which is
-- what makes "You have no room in your party" a thing you can be told while
-- already holding out your hands for the egg.
function DayCareMenu:startOutside()
  local dc = Breeding.dayCare(self.save)
  if not (dc and dc.hasEgg) then
    return self:say(self.TEXT.notYet, function() self:close() end)
  end
  self:ask(self.TEXT.foundAnEgg, function() self:takeEgg() end, function()
    -- .Declined -> .Load0: wScriptVar stays FALSE and he keeps the egg.
    self:say(self.TEXT.illKeepIt, function() self:close() end)
  end)
end

function DayCareMenu:takeEgg()
  local ok, reason = Breeding.collectEgg(self.data, self.save,
    { rng = self.rng, game = self.game })
  if not ok then
    -- .PartyFull is the ONE branch that sets wScriptVar to TRUE.
    if reason == Breeding.REFUSE_PARTY_FULL then self.scriptVar = 1 end
    return self:say(self.TEXT.noRoomForEgg, function() self:close() end)
  end
  local player = (self.save.player and self.save.player.name) or "<PLAYER>"
  self:say(self.TEXT.receivedEgg(player), function()
    self:playSfx(SFX_GET_EGG)
    self.delay = GET_EGG_FRAMES
    self:say(self.TEXT.takeGoodCare, function() self:close() end)
  end)
end

-- ---------------------------------------------------------------- update

function DayCareMenu:updateMessage(input)
  Typer.step(self)
  if Typer.typing(self) then return end
  if not (input:wasPressed("a") or input:wasPressed("b")) then return end
  local message = self.message
  if message.page < #message.pages then
    Typer.turn(self, message)
    return
  end
  self.message = nil
  if message.onDone then message.onDone() end
end

function DayCareMenu:updateConfirm(input)
  local confirm = self.confirm
  Typer.step(self)
  if Typer.typing(self) then return end
  -- The yes/no box only comes up on the string's LAST page.
  if confirm.page < #confirm.pages then
    if input:wasPressed("a") or input:wasPressed("b") then
      Typer.turn(self, confirm)
    end
    return
  end
  if input:wasPressed("up") or input:wasPressed("down") then
    confirm.choice = confirm.choice == 1 and 2 or 1
    return
  end
  -- YesNoMenuHeader has no STATICMENU_DISABLE_B, so B is NO.
  if input:wasPressed("b") then
    self.confirm = nil
    if confirm.onNo then confirm.onNo() end
    return
  end
  if input:wasPressed("a") then
    local yes = confirm.choice == 1
    self.confirm = nil
    if yes then
      if confirm.onYes then confirm.onYes() end
    elseif confirm.onNo then
      confirm.onNo()
    end
  end
end

function DayCareMenu:update(_dt)
  -- The party list is on top of the stack; it owns input until it pops.
  if self.picking then return end
  if self.delay > 0 then
    self.delay = self.delay - 1
    return
  end
  local input = self.game and self.game.input
  if not input then return end
  if self.message then return self:updateMessage(input) end
  if self.confirm then return self:updateConfirm(input) end
end

-- ------------------------------------------------------------------ draw

function DayCareMenu:drawTextBox(lines)
  Chrome.box(TEXT_BOX_X, TEXT_BOX_Y, TEXT_BOX_W, TEXT_BOX_H)
  for i, line in ipairs(lines or {}) do
    Chrome.print(line, TEXT_X, TEXT_Y + (i - 1) * TEXT_LINE)
  end
end

function DayCareMenu:drawYesNo(choice)
  Chrome.box(YESNO_X, YESNO_Y, YESNO_W, YESNO_H)
  Chrome.print(Strings("YES"), YESNO_X + 2, YESNO_Y + 1)
  Chrome.print(Strings("NO"), YESNO_X + 2, YESNO_Y + 3)
  Chrome.cursor(YESNO_X + 1, YESNO_Y + (choice == 1 and 1 or 3))
end

-- ../pokecrystal/engine/events/daycare.asm:107
function DayCareMenu:yesNoVisible()
  local confirm = self.confirm
  if not confirm or confirm.page < #confirm.pages then return false end
  return not Typer.typing(self)
end

function DayCareMenu:drawPanel()
  local typed = self.typer == nil or self.typer:done()
  if self.message then
    self:drawTextBox(Typer.text(self, self.message.pages[self.message.page]))
    if typed and self.message.page < #self.message.pages
      and Typer.arrowOn(self) then
      Chrome.print(DOWN_ARROW, ARROW_X, ARROW_Y)
    end
  elseif self.confirm then
    self:drawTextBox(Typer.text(self, self.confirm.pages[self.confirm.page]))
    if self:yesNoVisible() then
      self:drawYesNo(self.confirm.choice)
    elseif typed and Typer.arrowOn(self) then
      Chrome.print(DOWN_ARROW, ARROW_X, ARROW_Y)
    end
  else
    self:drawTextBox(nil)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function DayCareMenu:draw()
  self:drawPanel()
end

return DayCareMenu
