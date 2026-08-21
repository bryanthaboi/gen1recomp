-- Bill's PC withdraw / deposit list (engine/pokemon/bills_pc.asm).
--
-- The screen is transcribed from the ASM's own coordinates rather than laid
-- out by eye, because that is what makes it line up on the 8px grid:
--
--   BillsPC_BoxName        Textbox at (8,0), interior 10x1 -- the box name
--   BillsPC_RefreshTextboxes
--                          Textbox at (8,2), interior 10x10, then the two top
--                          corners are overwritten with └ and ┘ so the list
--                          box reads as hanging off the name box above it
--   .PlaceNickname         five nicknames from (9,4), two rows apart
--   PCMonInfo              clears (0,0) 8 wide x 15 tall for the left panel,
--                          puts the front pic at (1,4) as 7x7 tiles, the level
--                          at (1,12), the gender at (5,12) and the species
--                          name at (1,14)
--
-- `mode` picks which list is being browsed: "withdraw" reads the current box,
-- "deposit" reads the party, and "move" walks BOTH -- see below.
--
-- MOVE POKéMON W/O MAIL (_MovePKMNWithoutMail, engine/pokemon/bills_pc.asm:480)
-- is not a one-press operation on the cart and must not be one here.  Its
-- jumptable is .Init -> .Joypad -> .PrepSubmenu -> .MoveMonWOMailSubmenu ->
-- .PrepInsertCursor -> .Joypad2, i.e.
--
--   1. "Choose a <PK><MN>." over a list that left/right walks across the PARTY
--      (wBillsPC_LoadedBox == 0, BillsPC_BoxName's `.party` arm) and all
--      fourteen boxes, wrapping at both ends (BillsPC_PressLeft/PressRight)
--   2. A on a mon opens MOVE / STATS / CANCEL under "What's up?"
--      (PCString_WhatsUp, .MoveMonWOMailSubmenu)
--   3. MOVE backs the position up and asks "Move to where?"
--      (PCString_MoveToWhere) with an insert cursor the player drives to the
--      destination list AND the slot inside it
--   4. A there is BillsPC_CheckSpaceInDestination then
--      MovePKMNWithoutMail_InsertMon, which prints "Saving… Leave ON!" and
--      writes the mon into its new home; B restores the backed-up position and
--      goes back to step 1
--
-- Collapsing that into "A sends the mon to the next box with room" -- which is
-- what this screen used to do -- reads as the PC EATING the mon: it vanishes
-- from the list with no destination named and no line of text, and the player
-- has fourteen boxes to search to find out it still exists.

local Assets = require("src.render.Assets")
local Boxes = require("src.core.gen2.Boxes")
local Chrome = require("src.ui.gen2.Chrome")
local Font = require("src.render.Font")
local GbcPalette = require("src.render.GbcPalette")
local Mail = require("src.core.gen2.Mail")
local Palettes = require("src.world.gen2.Palettes")
local Screens = require("src.ui.Screens")
local Sound = require("src.core.Sound")
local Unown = require("src.core.gen2.Unown")

local BoxMenu = {}
BoxMenu.__index = BoxMenu
BoxMenu.isOpaque = true

-- BillsPC_NumMonsOnScreen is 5 for the withdraw/deposit lists.
local VISIBLE_ROWS = 5
local LIST_X, LIST_Y = 9, 4
local LIST_SPACING = 2
local PIC_X, PIC_Y = 1, 4

-- PadFrontpic pads a 5x5 or 6x6 pic into the 7x7 block, one blank column then
-- 7-size blank tiles per column (engine/gfx/load_pics.asm:342-386).
local PIC_PAD = { [7] = { 0, 0 }, [6] = { 1, 1 }, [5] = { 1, 2 } }

-- wBillsPC_LoadedBox: 0 is the PARTY, 1..NUM_BOXES are the boxes.  Only the
-- MOVE screen ever loads box 0; the withdraw and deposit lists are one list
-- each (BillsPC_BoxName reads the same byte for all three).
local PARTY_BOX = 0

-- .MoveMonWOMailSubmenu's .MenuData, verbatim.  RELEASE is NOT one of these --
-- it belongs to BillsPC_WithdrawMenu's four rows -- so nothing on this screen
-- can destroy a mon.
local MOVE_SUBMENU = { "MOVE", "STATS", "CANCEL" }

-- engine/pokemon/bills_pc.asm:472-478: BillsPC_Withdraw's menu rows.
local WITHDRAW_SUBMENU = { "WITHDRAW", "STATS", "RELEASE", "CANCEL" }

-- BillsPCDepositMenuHeader's .MenuData (engine/pokemon/bills_pc.asm:234-240).
local DEPOSIT_SUBMENU = { "DEPOSIT", "STATS", "RELEASE", "CANCEL" }

function BoxMenu:submenuRows()
  if self.mode == "move" then return MOVE_SUBMENU end
  if self.mode == "deposit" then return DEPOSIT_SUBMENU end
  return WITHDRAW_SUBMENU
end

-- MovePKMNWithoutMail_InsertMon's .Saving_LeaveOn, printed for 20 frames while
-- the mon is written into its new home.  It stays up here until a button
-- clears it, because it is also the only confirmation the player gets that the
-- mon moved and where it went.
local SAVING_LEAVE_ON = "Saving\xe2\x80\xa6 Leave ON!"

-- PCString_NoReleasingEGGS, printed by BillsPC_IsMonAnEgg with SFX_WRONG
-- (engine/pokemon/bills_pc.asm:1615-1631, string at :2200).
local NO_RELEASING_EGGS = "No releasing EGGS!"

function BoxMenu:wantsFillScale() return true end
function BoxMenu:drawsWidescreen() return true end

-- opts: save, mode ("withdraw" | "deposit" | "move"), onClose()
function BoxMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, BoxMenu)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.mode = opts.mode or "withdraw"
  self.onClose = opts.onClose
  local data = game and game.data or {}
  self.pokemon = opts.pokemon or data.pokemon
  self.palettes = opts.palettes or data.gen2Palettes
  -- EggPic has no data.pokemon row; it rides menu_gfx.eggHatch, and ICON_EGG
  -- stands in for a cache built before the extractor learned it.
  self.menuGfx = opts.menuGfx or data.gen2MenuGfx
  self.icons = opts.icons or data.gen2Icons
  self.boxIndex = self.save and self.save.currentBox or 1
  self.index = 1
  self.scroll = 0
  self.picCache = {}
  self.message = nil
  -- nil while the list is being browsed; "submenu" while MOVE/STATS/CANCEL is
  -- up, "insert" while the insert cursor is picking a destination.  Only the
  -- move screen has phases -- the other two lists act on A.
  self.phase = nil
  self.submenuIndex = 1
  return self
end

-- The PARTY is box 0 on the move screen and nowhere else.
function BoxMenu:isParty(index)
  if index == nil then index = self.boxIndex end
  return self.mode == "move" and index == PARTY_BOX
end

-- The mon list a given loaded box stands for.  Boxes.box hands back a live
-- table (and creates it on demand), so an insert here lands on the save.
function BoxMenu:listAt(index)
  if self:isParty(index) then
    self.save.party = self.save.party or {}
    return self.save.party
  end
  return Boxes.box(self.save, index)
end

-- PARTY_LENGTH for box 0, MONS_PER_BOX for the rest
-- (BillsPC_CheckSpaceInDestination's `.party` arm).
function BoxMenu:capacityAt(index)
  if self:isParty(index) then return Boxes.PARTY_SIZE end
  return Boxes.MONS_PER_BOX
end

-- BillsPC_BoxName: the party's name is a string of its own, a box's comes out
-- of wBoxNames.
function BoxMenu:nameAt(index)
  -- .PartyPKMN is "PARTY <PK><MN>@" -- eight tiles, because <PK> and <MN> are
  -- one font glyph each.
  if self:isParty(index) then return "PARTY <PK><MN>" end
  return Boxes.name(self.save, index)
end

-- Which list this mode browses.
function BoxMenu:list()
  if self.mode == "deposit" then return self.save.party or {} end
  return self:listAt(self.boxIndex)
end

function BoxMenu:title()
  if self.mode == "deposit" then return "PARTY <PK><MN>" end
  -- While the insert cursor is up the header names the DESTINATION: the whole
  -- screen has moved there (.PrepInsertCursor calls the same
  -- BillsPC_MoveMonWOMail_BoxNameAndArrows with the new wBillsPC_LoadedBox).
  return self:nameAt(self.boxIndex)
end

-- The cart's own prompts (PCString_*): short, because the box they print in
-- is one row of 18 columns.
function BoxMenu:prompt()
  -- engine/pokemon/bills_pc.asm:356-369: PrepSubmenu places PCString_WhatsUp.
  if self.phase == "submenu" then return "What's up?" end
  if self.mode == "move" then
    -- .Init and .PrepInsertCursor each place their own string.
    if self.phase == "insert" then return "Move to where?" end
    return "Choose a <PK><MN>."
  end
  -- PCString_ChooseaPKMN: _DepositPKMN.Init and BillsPC_Withdraw.Init both
  -- place this exact string (engine/pokemon/bills_pc.asm:2185).
  return "Choose a <PK><MN>."
end

function BoxMenu:total()
  return #self:list() + 1 -- CANCEL
end

function BoxMenu:isCancel()
  return self.index > #self:list()
end

function BoxMenu:selected()
  return self:list()[self.index]
end

function BoxMenu:ensureVisible()
  if self.index <= self.scroll then
    self.scroll = self.index - 1
  elseif self.index > self.scroll + VISIBLE_ROWS then
    self.scroll = self.index - VISIBLE_ROWS
  end
  self.scroll = math.max(0, math.min(self.scroll,
    math.max(0, self:total() - VISIBLE_ROWS)))
end

function BoxMenu:clampIndex()
  local total = self:total()
  if self.index > total then self.index = total end
  if self.index < 1 then self.index = 1 end
  self:ensureVisible()
end

function BoxMenu:act()
  if self:isCancel() then
    if self.onClose then self.onClose() end
    return
  end
  -- engine/pokemon/bills_pc.asm:336-344: withdraw and move both PrepSubmenu,
  -- and _DepositPKMN's .a_button steps to .WhatsUp the same way (:94-102).
  if not self:selected() then return end
  self.phase = "submenu"
  -- `ld a, $1 / ld [wMenuCursorY], a`: the submenu always opens on its top row.
  self.submenuIndex = 1
end

-- ------------------------------------------------------------ MOVE, step 2

-- BillsPC_CheckMail_PreventBlackout (engine/pokemon/bills_pc.asm:1575), which
-- .Move runs BEFORE it backs up the cursor: three refusals, all of them about
-- the PARTY, so a boxed mon walks straight past.  Returns true, or false and
-- the string the cart places.
function BoxMenu:checkMailPreventBlackout()
  -- `ld a, [wBillsPC_LoadedBox] / and a / jr nz, .Okay`; _DepositPKMN zeroes
  -- that byte too, so its list is the party (bills_pc.asm:17-18).
  if not (self:isParty() or self.mode == "deposit") then return true end
  local party = self.save.party or {}
  -- `cp $3 / jr c, .ItsYourLastPokemon`: a party of one or two may not send
  -- one away at all, however healthy the rest of it is.
  if #party < 3 then return false, "It's your last <PK><MN>!" end
  -- CheckCurPartyMonFainted (engine/pokemon/bills_pc_top.asm:171) walks the
  -- party skipping wCurPartyMon and answers carry when everything ELSE has
  -- fainted -- taking this one out would white the player out on the next step.
  local othersUsable = false
  for i, mon in ipairs(party) do
    if i ~= self.index and (mon.hp or 0) > 0 then othersUsable = true break end
  end
  if not othersUsable then return false, "No more usable <PK><MN>!" end
  -- wBillsPC_MonHasMail, the byte PCMonInfo set while drawing the row.  The
  -- top menu already refused to open this screen at all while any party mon
  -- holds a letter (BillsPC_MovePKMNMenu's IsAnyMonHoldingMail,
  -- src/ui/gen2/PcMenu.lua), so this is the second of two nets.
  if Mail.monHoldsMail(party[self.index]) then
    return false, "Remove MAIL."
  end
  return true
end

-- .Move: back the position up (so B can restore it), keep the loaded box and
-- step to $4, .PrepInsertCursor.
function BoxMenu:beginMove()
  local ok, reason = self:checkMailPreventBlackout()
  if not ok then
    -- BillsPC_PlaceString + SFX_WRONG + 50 frames, then `dec [hl]` drops back
    -- to the submenu; here the message holds until a button clears it and the
    -- list comes back, which is the same place the player ends up.
    self.phase = nil
    self.message = reason
    return
  end
  self.moveFrom = { box = self.boxIndex, slot = self.index }
  self.backup = { box = self.boxIndex, index = self.index, scroll = self.scroll }
  self.phase = "insert"
  self:clampInsert()
end

-- BillsPC_StatsScreen: the stats screen over the selected mon, then back to
-- the submenu (.Stats ends in PCMonInfo, not in a jumptable step).
function BoxMenu:openStats()
  local mon = self:selected()
  local game = self.game
  if not (mon and game and game.stack) then return end
  if not pcall(Screens.get, game, "Gen2SummaryMenu") then return end
  Screens.push(game, "Gen2SummaryMenu", {
    mon = mon,
    save = self.save,
    onClose = function() game.stack:pop() end,
  })
end

-- engine/pokemon/bills_pc.asm:397-411: failed withdraw stays on the submenu.
function BoxMenu:doWithdraw()
  local ok, result = Boxes.withdraw(self.save, self.boxIndex, self.index)
  if not ok then
    self.message = result
    return
  end
  self.message = nil
  self.phase = nil
  self:clampIndex()
end

-- engine/pokemon/bills_pc.asm:155 BillsPCDepositFuncDeposit
function BoxMenu:doDeposit()
  local ok, result = Boxes.deposit(self.save, self.index, self.boxIndex)
  if not ok then
    self.message = result
    return
  end
  self.message = nil
  self.phase = nil
  self.index, self.scroll = 1, 0
  self:clampIndex()
end

function BoxMenu:chooseSubmenu()
  local row = self:submenuRows()[self.submenuIndex]
  if row == "MOVE" then
    self:beginMove()
  elseif row == "DEPOSIT" then
    self:doDeposit()
  elseif row == "WITHDRAW" then
    self:doWithdraw()
  elseif row == "STATS" then
    self:openStats()
  elseif row == "RELEASE" then
    self:askRelease()
  else
    -- .Cancel: `ld a, $0 / ld [wJumptableIndex], a`.
    self.phase = nil
  end
end

-- ------------------------------------------------------------ MOVE, step 3

-- How many insert positions the destination offers.  BillsPC_PressDown stops
-- at wBillsPC_NumMonsInBox - 1, so the cursor always sits ON a mon (or on row
-- one of an empty list) and InsertSpeciesIntoBoxOrParty pushes the rest down.
function BoxMenu:insertPositions()
  return math.max(1, #self:listAt(self.boxIndex))
end

function BoxMenu:clampInsert()
  self.index = math.max(1, math.min(self.index, self:insertPositions()))
  self.scroll = math.max(0, math.min(self.scroll,
    math.max(0, self:insertPositions() - VISIBLE_ROWS)))
  if self.index <= self.scroll then
    self.scroll = self.index - 1
  elseif self.index > self.scroll + VISIBLE_ROWS then
    self.scroll = self.index - VISIBLE_ROWS
  end
end

-- BillsPC_CheckSpaceInDestination: a move inside one list is always allowed
-- (`.same_box`), and a move into another one needs a free slot there.  The
-- ASM compares against MONS_PER_BOX + 1 / PARTY_LENGTH + 1, which can never be
-- reached -- the port refuses at the real capacity instead, because a 21st mon
-- in a box is a mon the save cannot hold.
function BoxMenu:checkSpaceInDestination()
  local from = self.moveFrom
  if from and from.box == self.boxIndex then return true end
  if #self:listAt(self.boxIndex) >= self:capacityAt(self.boxIndex) then
    return false, "There's no room!"
  end
  return true
end

-- MovePKMNWithoutMail_InsertMon's .Jumptable: .BoxToBox / .PartyToBox /
-- .BoxToParty / .PartyToParty, all four of them .CopyFrom* (which is
-- RemoveMonFromPartyOrBox) followed by .CopyTo* (InsertPokemonIntoBox or
-- InsertPokemonIntoParty).  This port keeps a mon as one Lua table in exactly
-- one list, so the four cases are one remove and one insert; what differs is
-- WHICH list each end names, and the mail bookkeeping on the party end.
function BoxMenu:insertMon()
  local from = self.moveFrom
  if not from then return end
  local source = self:listAt(from.box)
  local mon = source[from.slot]
  if not mon then
    self.phase = nil
    self.moveFrom, self.backup = nil, nil
    return
  end
  local destIndex = self.boxIndex
  local target = math.min(self.index, self:insertPositions())
  table.remove(source, from.slot)
  -- sPartyMail is keyed by party SLOT, so a mon leaving the party drags every
  -- letter behind it up one (RemoveMonFromPartyOrBox's "Mail time!" tail, the
  -- same call Boxes.deposit makes).  No letter can actually be in the party
  -- here -- IsAnyMonHoldingMail refused the whole screen -- so this keeps the
  -- slots honest rather than moving anything.
  if self:isParty(from.box) then Mail.removeSlot(self.save, from.slot) end
  local dest = self:listAt(destIndex)
  if from.box == destIndex and target > from.slot then
    -- .CheckTrivialMove: the source was taken out first, so a destination slot
    -- below it has already shuffled up one.
    target = target - 1
  end
  table.insert(dest, math.max(1, math.min(target, #dest + 1)), mon)
  -- .CopyToBox is InsertPokemonIntoBox, which tails into
  -- RestorePPOfDepositedPokemon (engine/pokemon/move_mon_wo_mail.asm:35-37).
  if not self:isParty(destIndex) then Boxes.restorePP(mon) end
  self.phase = nil
  self.moveFrom, self.backup = nil, nil
  self.index, self.scroll = 1, 0
  self:clampIndex()
  self.message = SAVING_LEAVE_ON
end

-- .b_button_2: the backed-up scroll, cursor and loaded box all go back, and
-- the screen returns to step 1 with nothing moved.
function BoxMenu:cancelMove()
  local backup = self.backup
  if backup then
    self.boxIndex, self.index, self.scroll =
      backup.box, backup.index, backup.scroll
  end
  self.phase = nil
  self.moveFrom, self.backup = nil, nil
  self:clampIndex()
end

-- BillsPC_PressLeft / BillsPC_PressRight.  The move screen wraps through box 0
-- (the PARTY); the withdraw list has no party to walk into, so it wraps inside
-- the fourteen boxes.
function BoxMenu:stepBox(delta)
  local low = self.mode == "move" and PARTY_BOX or 1
  local span = Boxes.NUM_BOXES - low + 1
  self.boxIndex = (self.boxIndex - low + delta) % span + low
  -- .dpad / .dpad_2: both arms zero the cursor and the scroll.
  self.index, self.scroll = 1, 0
  if self.phase == "insert" then self:clampInsert() end
end

function BoxMenu:update(_dt)
  local input = self.game and self.game.input
  if not input then return end

  if self.message then
    if input:wasPressed("a") or input:wasPressed("b") then
      self.message = nil
    end
    return
  end

  -- .MoveMonWOMailSubmenu, a VerticalMenu: up/down, A picks, B is its carry.
  if self.phase == "submenu" then
    local submenu = self:submenuRows()
    if input:wasPressed("up") then
      self.submenuIndex = self.submenuIndex > 1 and self.submenuIndex - 1
        or #submenu
    elseif input:wasPressed("down") then
      self.submenuIndex = self.submenuIndex < #submenu
        and self.submenuIndex + 1 or 1
    elseif input:wasPressed("a") then
      self:chooseSubmenu()
    elseif input:wasPressed("b") then
      self.phase = nil
    end
    return
  end

  -- .Joypad2: the insert cursor.  Up/down walk the destination's slots,
  -- left/right walk the destinations themselves, A inserts, B goes back.
  if self.phase == "insert" then
    local positions = self:insertPositions()
    if input:wasPressed("up") then
      self.index = self.index > 1 and self.index - 1 or positions
      self:clampInsert()
    elseif input:wasPressed("down") then
      self.index = self.index < positions and self.index + 1 or 1
      self:clampInsert()
    elseif input:wasPressed("left") then
      self:stepBox(-1)
    elseif input:wasPressed("right") then
      self:stepBox(1)
    elseif input:wasPressed("a") then
      local ok, reason = self:checkSpaceInDestination()
      if not ok then
        -- .no_space: `dec [hl]` puts the jumptable back on .PrepInsertCursor,
        -- so the refusal leaves the cursor exactly where it was.
        self.message = reason
      else
        self:insertMon()
      end
    elseif input:wasPressed("b") then
      self:cancelMove()
    end
    return
  end

  local total = self:total()
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or total
    self:ensureVisible()
  elseif input:wasPressed("down") then
    self.index = self.index < total and self.index + 1 or 1
    self:ensureVisible()
  elseif input:wasPressed("left") and self.mode ~= "deposit" then
    self:stepBox(-1)
  elseif input:wasPressed("right") and self.mode ~= "deposit" then
    self:stepBox(1)
  elseif input:wasPressed("a") then
    self:act()
  -- RELEASE and the nickname keyboard are BillsPC_WithdrawMenu's and the
  -- CHANGE BOX menu's rows; .MoveMonWOMailSubmenu has neither, and a stray
  -- SELECT on the move screen must not put "Release <PK><MN>?" in front of a
  -- player who only meant to reorder a box.
  elseif input:wasPressed("select") and self.mode == "withdraw" then
    self:askRelease()
  elseif input:wasPressed("start") and self.mode == "withdraw" then
    self:askNickname()
  elseif input:wasPressed("b") then
    if self.onClose then self.onClose() end
  end
end

function BoxMenu:playSfx(name)
  local data = self.game and self.game.data
  local sfx = data and data.audio and data.audio.sfx
  if sfx and sfx[Sound.resolve(data, name)] then Sound.play(data, name) end
end

-- BillsPC's RELEASE, which the model has always supported and nothing on
-- screen reached.  The cart asks first and starts the prompt on NO, the way
-- every irreversible choice in the game does.
function BoxMenu:askRelease()
  if self:isCancel() then return end
  local mon = self:selected()
  if not mon then return end
  -- BillsPCDepositFuncRelease runs the mail/blackout net BEFORE the egg check
  -- (engine/pokemon/bills_pc.asm:183-187).
  if self.mode == "deposit" then
    local allowed, refusal = self:checkMailPreventBlackout()
    if not allowed then
      self.phase = nil
      self.message = refusal
      return
    end
  end
  -- Both release paths run BillsPC_IsMonAnEgg first, so the question is never
  -- even asked over an egg (engine/pokemon/bills_pc.asm:186-187 and :427-428).
  if mon.isEgg then
    self.message = NO_RELEASING_EGGS
    self:playSfx("Sfx_Wrong")
    return
  end
  local game = self.game
  if not (game and game.stack) then return end
  local ChoiceBox = require("src.ui.ChoiceBox")
  local name = mon.nickname or mon.name or mon.species or "?"
  game.stack:push(ChoiceBox.new(game, function(yes)
    if not yes then return end
    local ok, err
    if self.mode == "deposit" then
      ok, err = Boxes.releaseFromParty(self.save, self.index)
    else
      ok, err = Boxes.release(self.save, self.boxIndex, self.index)
    end
    if not ok then
      self.message = err
      return
    end
    self.message = name .. " was released."
    self.phase = nil
    self:clampIndex()
  end, { defaultNo = true }))
end

-- The naming screen the cart opens from BillsPC's own nickname option.
function BoxMenu:askNickname()
  if self:isCancel() then return end
  local mon = self:selected()
  if not mon then return end
  local game = self.game
  if not (game and game.stack) then return end
  -- The resolve is guarded rather than the construction: a keyboard that will
  -- not even load is a nickname the player cannot type, not a crash.  Same
  -- shape as the openscreen script command (src/script/Commands.lua).
  if not pcall(Screens.get, game, "Gen2NamingScreen") then return end
  Screens.push(game, "Gen2NamingScreen", {
    -- The "nickname" kind is MON_NAME_LENGTH - 1 wide and takes its header
    -- from the mon rather than from a fixed prompt.
    type = "nickname",
    monName = mon.name or mon.species,
    initial = mon.nickname or "",
    onDone = function(name)
      game.stack:pop()
      if name and #name > 0 then mon.nickname = name end
    end,
    onCancel = function() game.stack:pop() end,
  })
end

function BoxMenu:image(path)
  if not path then return nil end
  local cached = self.picCache[path]
  if cached == nil then
    -- `and` truncates a multi-return, so the pcall has to stand alone.
    local ok, image = pcall(Assets.image, path)
    cached = (ok and image) or false
    self.picCache[path] = cached
  end
  return cached or nil
end

-- The selected mon's front pic, cached per species.
function BoxMenu:picFor(mon)
  if not (mon and mon.species and self.pokemon) then return nil end
  local def = self.pokemon[mon.species]
  local path = def and def.spriteFront
  -- BillsPC_LoadMonStats' frontpic (engine/pokemon/bills_pc.asm:1048-1052) runs
  -- `ld hl, wTempMonDVs / predef GetUnownLetter` before GetBaseData, and the
  -- D-pad reload at :1667-1668 does the same, so a stored Unown previews its
  -- OWN form.  The species row is letter A's pic, which is what the cart shows
  -- only when the DVs actually say A.
  if mon.species == Unown.SPECIES then
    path = Unown.formSprite(self.pokemon, Unown.monLetter(mon)) or path
  end
  return self:image(path)
end

-- PCMonInfo lays the padded pic as one 7x7 block at hlcoord 1, 4
-- (engine/pokemon/bills_pc.asm:1023-1042), the pad tiles at the palette's 0.
function BoxMenu:drawPicBlock(image, colors)
  if not image then return end
  local G = love.graphics
  local blank = colors and GbcPalette.color(colors, 1) or { 255, 255, 255 }
  G.setColor(blank[1] / 255, blank[2] / 255, blank[3] / 255, 1)
  G.rectangle("fill", PIC_X * 8, PIC_Y * 8, 7 * 8, 7 * 8)

  local pad = PIC_PAD[math.floor(image:getWidth() / 8)] or PIC_PAD[7]
  G.setColor(1, 1, 1, 1)
  local function body()
    G.draw(image, (PIC_X + pad[1]) * 8, (PIC_Y + pad[2]) * 8)
  end
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, body)
  else
    body()
  end
  G.setColor(1, 1, 1, 1)
end

function BoxMenu:drawPic(mon)
  local image = self:picFor(mon)
  if not image then return end
  -- _CGB_BillsPC hands wTempMonDVs to GetPlayerOrMonPalettePointer, so the box
  -- pic takes the shiny row (engine/gfx/cgb_layouts.asm:292-293).
  local colors = self.palettes
    and Palettes.monColors(self.palettes, mon.species, mon.shiny)
  self:drawPicBlock(image, colors)
end

-- GetFrontpic's `cp EGG / jr nz, .not_egg` arm hands back EggPic, never the
-- hatchling's pic (engine/gfx/load_pics.asm:88-91); it rides menu_gfx.eggHatch,
-- with the party list's ICON_EGG standing in for a cache built before that.
function BoxMenu:drawEggPic(mon)
  local G = love.graphics
  local colors = self.palettes
    and Palettes.monColors(self.palettes, "EGG", mon and mon.shiny)
  local gfx = (self.menuGfx or {}).eggHatch
  local image = self:image(gfx and gfx.egg)
  if image then return self:drawPicBlock(image, colors) end
  local entry = self.icons and self.icons.icons and self.icons.icons.ICON_EGG
  image = self:image(entry and entry.image)
  if not image then return end
  local blank = colors and GbcPalette.color(colors, 1) or { 255, 255, 255 }
  G.setColor(blank[1] / 255, blank[2] / 255, blank[3] / 255, 1)
  G.rectangle("fill", PIC_X * 8, PIC_Y * 8, 7 * 8, 7 * 8)
  -- The ICON_EGG sheet stacks its frames; the first is the egg at rest.
  local w = entry.width or 16
  local h = math.min(entry.height or 16, image:getHeight())
  if (entry.frames or 1) > 1 then h = math.floor(h / entry.frames) end
  local ok, quad = pcall(love.graphics.newQuad, 0, 0, w, h,
    image:getWidth(), image:getHeight())
  if not ok then return end
  local x = PIC_X * 8 + math.floor((7 * 8 - w * 2) / 2)
  local y = PIC_Y * 8 + math.floor((7 * 8 - h * 2) / 2)
  G.setColor(1, 1, 1, 1)
  local function body() G.draw(image, quad, x, y, 0, 2, 2) end
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, body)
  else
    body()
  end
  G.setColor(1, 1, 1, 1)
end

-- The PC does not mark the selected row with a ▶: BillsPC_UpdateSelectionCursor
-- lays 20 OBJs as a frame *around* the row -- ten tiles wide by two tall, top
-- left at pixel (71, 25), stepping 16 pixels per row.  Those cursor tiles are
-- not extracted, so the frame is drawn as an outline at exactly those pixels,
-- which is what the sprite frame looks like.
function BoxMenu:drawSelectionFrame(row)
  local G = love.graphics
  local x, y = 71, 25 + (row - 1) * 16
  G.setColor(0, 0, 0, 1)
  G.setLineWidth(1)
  G.rectangle("line", x + 0.5, y + 0.5, 80 - 1, 16 - 1)
  G.setLineWidth(1)
end

-- BillsPC_UpdateInsertCursor lays a DIFFERENT sprite frame from the selection
-- one -- a wedge between the rows rather than a box around one -- so the
-- insert cursor is drawn as a rule along the top edge of the row the mon is
-- going in front of.
function BoxMenu:drawInsertCursor(row)
  local G = love.graphics
  local x, y = 71, 31 + (row - 1) * 16
  G.setColor(0, 0, 0, 1)
  G.rectangle("fill", x, y, 80, 2)
end

-- The mon the whole screen is about while the insert cursor is up: .PrepSubmenu
-- ran PCMonInfo over it and .PrepInsertCursor does NOT run it again, so the
-- left panel keeps showing the mon in flight.
function BoxMenu:panelMon()
  local from = self.moveFrom
  if self.phase == "insert" and from then
    return self:listAt(from.box)[from.slot]
  end
  return self:selected()
end

function BoxMenu:drawPanel()
  -- BillsPC_InitGFX loads FontsBattleExtra once for the whole screen and
  -- never restores the standard font (engine/pokemon/bills_pc.asm:2169).
  local wasBattle = Font.useBattleExtra(true)
  Chrome.clear()

  -- Box name header, then the list box hanging off it.  BillsPC_BoxName is a
  -- Textbox at (8,0) with a 10x1 interior and the name at (10,1).
  Chrome.box(8, 0, 12, 3)
  Chrome.print(self:title(), 10, 1)
  Chrome.box(8, 2, 12, 12)
  -- BillsPC_RefreshTextboxes overwrites its own top corners with '└'/'┘'
  -- (engine/pokemon/bills_pc.asm:1204-1211) so the list reads as hanging
  -- off the name box above it.
  Font.drawCode(Font.BORDER.bl, 8 * 8, 2 * 8)
  Font.drawCode(Font.BORDER.br, 19 * 8, 2 * 8)

  local list = self:list()
  local inserting = self.phase == "insert"
  for row = 1, VISIBLE_ROWS do
    local i = row + self.scroll
    local ty = LIST_Y + (row - 1) * LIST_SPACING
    if i <= #list then
      local mon = list[i]
      if i == self.index then
        if inserting then
          self:drawInsertCursor(row)
        else
          self:drawSelectionFrame(row)
        end
      end
      -- .PlaceNickname prints the stored nickname bytes verbatim, with no egg
      -- check of its own (engine/pokemon/bills_pc.asm:1245-1356).
      local label = mon.nickname or mon.name or mon.species or "?"
      Chrome.print(label, LIST_X, ty)
    elseif inserting then
      -- An empty destination: the cursor is the only thing on the list.
      if i == self.index then self:drawInsertCursor(row) end
    elseif i == self:total() then
      if i == self.index then self:drawSelectionFrame(row) end
      Chrome.print("CANCEL", LIST_X, ty)
    end
  end

  -- The left panel: pic, level, gender, species -- blank on CANCEL, the way
  -- PCMonInfo clears it when the selection is not a mon.
  local mon = self:panelMon()
  if mon then
    -- `cp EGG / ret z` right after the frontpic: no name, no level, no gender
    -- (engine/pokemon/bills_pc.asm:1057-1058).
    if mon.isEgg then
      self:drawEggPic(mon)
    else
      self:drawPic(mon)
      -- PrintLevel always writes the single bold glyph, not ":L"
      -- (home/pokemon.asm:178-183).
      Chrome.print("<LV>" .. tostring(mon.level or 1), PIC_X, 12)
      if mon.gender == "male" then
        Chrome.print("\xe2\x99\x82", 5, 12)
      elseif mon.gender == "female" then
        Chrome.print("\xe2\x99\x80", 5, 12)
      end
      Chrome.print(mon.name or mon.species or "?", PIC_X, 14)
    end
  end

  -- BillsPC_PlaceString: Textbox at (0,15) with a one-row interior, string at
  -- (1,16).  A refusal is two lines on the cart, so those get a taller box of
  -- their own rather than being cut to fit this one.
  if self.message then
    Chrome.box(0, 12, 20, 6)
    -- Two lines, two tile rows apart, the way every other text box lays out.
    local line = 14
    for part in (self.message .. "\n"):gmatch("(.-)\n") do
      Chrome.print(part, 1, line)
      line = line + 2
    end
  else
    Chrome.box(0, 15, 20, 3)
    Chrome.print(self:prompt(), 1, 16)
  end

  -- .MoveMonWOMailSubmenu's .MenuHeader is `menu_coords 9, 4, SCREEN_WIDTH - 1,
  -- 13` -- it covers the nickname list, which is why the list is still drawn
  -- underneath it and not instead of it.  STATICMENU_CURSOR with the default
  -- top spacing puts MOVE at (11,6), one row per two tiles.
  if self.phase == "submenu" then
    Chrome.box(9, 4, 11, 10)
    for i, label in ipairs(self:submenuRows()) do
      local ty = 6 + (i - 1) * 2
      if i == self.submenuIndex then Chrome.cursor(10, ty) end
      Chrome.print(label, 11, ty)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  Font.useBattleExtra(wasBattle)
end

function BoxMenu:draw()
  self:drawPanel()
end

function BoxMenu:drawWidescreen(winW, winH)
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

return BoxMenu
