-- Gold's START menu (engine/menus/start_menu.asm StartMenu).
--
-- The box is right-aligned -- menu_coords 10, 0, SCREEN_WIDTH - 1,
-- SCREEN_HEIGHT - 1 -- and grows to fit however many entries are currently
-- unlocked.  #DEX and POKEGEAR only appear once the player owns them, so early
-- in the game the menu is short; the ASM builds wMenuItemsList each time it
-- opens for exactly that reason (.SetUpMenuItems).
--
-- With MENU ACCOUNT on, a second box at the bottom-left describes the
-- highlighted entry (.MenuDesc), which is why every item carries two lines of
-- description text here.
--
-- The cursor position is remembered between openings
-- (wBattleMenuCursorPosition), so reopening the menu lands where you left it.
--
-- The assembled list runs through the ui.start_menu.items hook before the menu
-- opens, exactly as the Gen 1 port's does (src/ui/StartMenu.lua), so mods
-- insert, drop or reorder rows without patching this file.  It is the SAME
-- hook name and the same (game, items) payload: Gold's POKEGEAR row is simply
-- one more entry in the list the hook receives.

local BugContest = require("src.core.gen2.BugContest")
local Chrome = require("src.ui.gen2.Chrome")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")

local StartMenu = {}
StartMenu.__index = StartMenu
-- Not opaque: the overworld keeps drawing underneath, the way the real menu
-- slides a window over the map.
StartMenu.isOpaque = false

-- SFX_MENU on open, SFX_READ_TEXT_2 (the click) on select
-- (StartMenu_Show's `ld de, SFX_MENU / call PlaySFX` and .Select's
-- PlayClickSFX).  By LABEL, not index: the old numeric ids (2 and 3) landed
-- on whatever the sfx table had there -- the item-get jingle on every menu
-- open -- and a repointed table would drift again.

-- STARTMENUITEM_* in the order .SetUpMenuItems appends them.  `need` is the
-- save flag that unlocks the entry; nil means always shown.
--
-- Labels are the ASM's own strings, with the compression bytes expanded the
-- way the cart expands them at print time: "#DEX" is POKé + DEX (seven tiles),
-- while "<POKE>GEAR" is <PO><KE>GEAR -- the <PO> and <KE> glyphs ($70/$71) are
-- one tile each, so that row is six tiles wide, not eight.  That difference is
-- exactly what kept POKéGEAR hanging off the menu box's right edge.
local ITEMS = {
  {
    id = "pokedex", label = Strings.source("POKéDEX"), need = "pokedex",
    desc = Strings.source("POKéMON\ndatabase"),
  },
  {
    id = "pokemon", label = Strings.source("POKéMON"), need = "party",
    desc = Strings.source("Party <PK><MN>\nstatus"),
  },
  {
    id = "pack", label = Strings.source("PACK"), need = "pack",
    desc = Strings.source("Contains\nitems"),
  },
  {
    id = "pokegear", label = Strings.source("<PO><KE>GEAR"), need = "pokegear",
    desc = Strings.source("Trainer's\nkey device"),
  },
  {
    -- The player's own name is the label (.StatusString is "<PLAYER>").
    id = "status", label = nil,
    desc = Strings.source("Your own\nstatus"),
  },
  {
    id = "save", label = Strings.source("SAVE"),
    desc = Strings.source("Save your\nprogress"),
  },
  {
    id = "option", label = Strings.source("OPTION"),
    desc = Strings.source("Change\nsettings"),
  },
  {
    -- The mod manager's discoverable home, exactly as the Gen 1 start menu
    -- carries it: the row only appears once at least one mod has been
    -- discovered, so a vanilla install's menu is the cart's.
    id = "mods", label = Strings.source("MODS"), need = "mods",
    desc = Strings.source("Installed\nadd-ons"),
  },
  {
    -- The cart's EXIT just closed the menu (CloseStartMenu).  A window with a
    -- close button already covers that, so -- exactly as the Gen 1 port does
    -- (src/ui/StartMenu.lua) -- this row is QUIT and power-cycles back to the
    -- title after a confirmation that defaults to NO.
    id = "quit", label = Strings.source("QUIT"),
    desc = Strings.source("Return to\nthe title"),
  },
}

-- The confirmation's yes/no box.  A bare YesNoBox lands at YesNoMenuHeader's
-- own menu_coords 10, 5, 15, 9, which is exactly where the start menu is, so
-- this uses the other position the cart already places one at:
-- SaveTheGame_yesorno's `lb bc, 0, 7`, a 6x5 box at (0,7) clear of the menu.
-- Labels sit at (2,8) and (2,10) -- border + 1, plus a column for
-- STATICMENU_CURSOR and no extra row because STATICMENU_NO_TOP_SPACING is set.
local YESNO_X, YESNO_Y, YESNO_W, YESNO_H = 0, 7, 6, 5

-- Persisted across openings, like wBattleMenuCursorPosition.
StartMenu.lastIndex = 1

-- ui.start_menu.items identity: an unhooked build hands its own list back.
local function sameItems(_, items) return items end

-- opts: save, onChoose(id), onClose(), unlocked (override table for tests)
function StartMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, StartMenu)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.onChoose = opts.onChoose
  self.onClose = opts.onClose
  self.unlocked = opts.unlocked
  local items = self:visibleItems()
  -- Unguarded, like the Gen 1 site: the menu is built once per opening, not
  -- per frame, so there is nothing here worth a wantsHook fast path.  A hook
  -- that answers with anything but a table is degraded to the vanilla list
  -- rather than emptying the player's menu.
  local hooked = Runtime.call("ui.start_menu.items", sameItems, game, items)
  if type(hooked) == "table" then
    items = hooked
  else
    Logger.error("ui.start_menu.items returned %s; keeping the vanilla items",
                 type(hooked))
  end
  -- Let hooks inspect the cart's stable source labels. Translate only the
  -- built-in rows afterwards; mod-supplied labels are content and stay raw.
  for _, item in ipairs(items) do
    if item.translateLabel then item.label = Strings(item.label) end
    if item.translateDesc then
      local translated = Strings(item.desc)
      item.desc = {}
      for line in (translated .. "\n"):gmatch("(.-)\n") do
        item.desc[#item.desc + 1] = line
      end
    end
  end
  self.items = items
  local options = (self.save and self.save.options) or {}
  self.showDescription = options.menuAccount ~= false

  self.list = Chrome.List.new({
    items = self.items,
    -- GetMenuTextStartCoord: the box's left/top plus one for the border, plus
    -- one more for the cursor column (STATICMENU_CURSOR) and one more for the
    -- top spacing this menu does not opt out of -- so (10,0) becomes (12,2),
    -- and Chrome.List puts the cursor at x - 1 = 11.
    -- pokecrystal engine/menus/start_menu.asm:164
    x = 12, y = self.contest and 4 or 2, spacing = 2,
    -- Two rows per entry inside an 18-row screen leaves room for eight, which
    -- is exactly the vanilla count.  A mod that adds a row scrolls rather than
    -- drawing off the bottom of the frame; Chrome.List puts the ▼ hint on.
    rows = math.min(#self.items, 8),
    wrap = true,
    startAccepts = true,
    index = math.min(StartMenu.lastIndex, math.max(1, #self.items)),
    onChoose = function(value, index) self:choose(value, index) end,
    onCancel = function() self:close() end,
  })
  return self
end

-- Which entries the player has unlocked.  Derived from the save so the menu
-- grows as the game does; `unlocked` overrides it wholesale for tests.
-- .SetUpMenuItems tests two ENGINE flag bits, and both arrive as `setflag`
-- ids in save.engineFlags (constants/engine_flags.asm const order, via
-- World:setEngineFlag): `bit STATUSFLAGS_POKEDEX_F, [wStatusFlags]` is
-- ENGINE_POKEDEX = 11, written by Oak at Mr. Pokemon's house, and
-- `bit POKEGEAR_OBTAINED_F, [wPokegearFlags]` is ENGINE_POKEGEAR = 4,
-- written by Mom on the way out the door.
local ENGINE_POKEGEAR, ENGINE_POKEDEX = 4, 11

function StartMenu:availability()
  if self.unlocked then return self.unlocked end
  local save = self.save or {}
  local inventory = save.inventory or {}
  local engine = save.engineFlags or {}
  local status = self.game and self.game.modStatus
  return {
    mods = status ~= nil and #(status.available or {}) > 0,
    -- ENGINE_POKEDEX first; pokedexReceived stays as the test/driver override.
    pokedex = engine[ENGINE_POKEDEX] == true or save.pokedexReceived == true,
    party = #(save.party or {}) > 0,
    -- The PACK exists from the start; the cart gates it on nothing.
    pack = true,
    pokegear = engine[ENGINE_POKEGEAR] == true
      or (inventory.POKEGEAR or 0) > 0 or save.pokegearReceived == true,
  }
end

function StartMenu:visibleItems()
  local available = self:availability()
  local contest = BugContest.isActive(self.save)
  self.contest = contest
  local playerName = (self.save and self.save.player and self.save.player.name)
    or "GOLD"
  local out = {}
  for _, item in ipairs(ITEMS) do
    local id = item.id
    -- pokecrystal engine/menus/start_menu.asm:309
    local hidden = contest and (id == "pack" or id == "quit")
    if not hidden and (not item.need or available[item.need]) then
      if contest and id == "save" then
        -- pokecrystal engine/menus/start_menu.asm:330
        out[#out + 1] = {
          label = Strings.source("QUIT"), value = "quitContest",
          -- pokecrystal engine/menus/start_menu.asm:231
          desc = Strings.source("Quit and\nbe judged."),
          translateLabel = true,
          translateDesc = true,
        }
      else
        out[#out + 1] = {
          label = item.label or playerName,
          value = id,
          desc = item.desc,
          translateLabel = item.label ~= nil,
          translateDesc = item.desc ~= nil,
        }
      end
    end
  end
  return out
end

function StartMenu:playSfx(name)
  local data = self.game and self.game.data
  local audio = data and data.audio
  if not audio then return end
  if audio.sfx and audio.sfx[name] then Sound.play(data, name) end
end

function StartMenu:enter()
  self:playSfx("Sfx_Menu")
end

-- index comes from Chrome.List (src/ui/gen2/Chrome.lua:346) so a hook-injected
-- entry can be found by position: a mod's row carries an onSelect callback and
-- no `value`, the way the Gen 1 menu's rows do (src/ui/StartMenu.lua:30), and
-- without this arm it falls off the end of the id chain in Game2:switch.
function StartMenu:choose(id, index)
  StartMenu.lastIndex = self.list.index
  local item = index and self.items[index]
  if item and item.onSelect and item.value == nil then
    self:playSfx("Sfx_ReadText2")
    item.onSelect(self.game)
    return
  end
  self:playSfx("Sfx_ReadText2")
  if id == "quit" then
    -- Ask before throwing away everything since the last save.  NO is the
    -- default, the way the Gen 1 port's QUIT is.
    self.phase = "confirm"
    self.confirmChoice = 2
    return
  end
  if id == "quitContest" then
    -- pokecrystal engine/menus/start_menu.asm:411
    self.phase = "confirmContest"
    self.confirmChoice = 1
    return
  end
  if self.onChoose then self.onChoose(id) end
end

function StartMenu:confirmQuit()
  self.phase = nil
  if self.onQuit then
    self.onQuit()
  elseif self.game and self.game.returnToTitle then
    self.game:returnToTitle()
  end
end

-- pokecrystal engine/events/bug_contest/contest.asm:31
function StartMenu:confirmQuitContest()
  self.phase = nil
  self:close()
  local world = self.game and self.game.world
  if world and world.bugContestResults then world:bugContestResults() end
end

function StartMenu:close()
  StartMenu.lastIndex = self.list.index
  if self.onClose then self.onClose() end
end

function StartMenu:update(_dt)
  local input = self.game and self.game.input
  if not input then return end
  if self.phase == "confirm" or self.phase == "confirmContest" then
    if input:wasPressed("up") or input:wasPressed("down") then
      self.confirmChoice = self.confirmChoice == 1 and 2 or 1
    elseif input:wasPressed("a") then
      if self.confirmChoice ~= 1 then
        self.phase = nil
      elseif self.phase == "confirmContest" then
        self:confirmQuitContest()
      else
        self:confirmQuit()
      end
    elseif input:wasPressed("b") or input:wasPressed("start") then
      self.phase = nil
    end
    return
  end
  -- START closes the menu as well as opening it.
  if input:wasPressed("start") then
    self:close()
    return
  end
  self.list:update(input)
end

-- pokecrystal engine/menus/menu_2.asm:145
-- The box is two rows tall (y 14/16, step 2), which the cart's own line
-- break fills exactly. A translation can need a third line, and printWrapped
-- would drop it without a word, so say so once instead of shipping a prompt
-- that reads as a sentence cut in half.
-- The confirmation box at (0, 12, 18, 4) holds exactly two rows, which the
-- cart's own line break fills.  A translation can need a third, which would be
-- dropped without a word, so this says so once per prompt.  printWrapped
-- returns the line count it wrapped to, so the box's own draw is what reports
-- the overflow: no second wrap, and no way for the two to disagree on the
-- width later.  It also wraps on pixel width, unlike a `\n`-only splitter,
-- which would hand Font.draw an embedded break -- rendered as a space -- and
-- run a long translated row past the box edge.
local promptWarned = {}
local function twoRowPrompt(text, what)
  local lines = Chrome.printWrapped(text, 1, 14, 18, 2, 2)
  if lines > 2 and not promptWarned[what] then
    promptWarned[what] = true
    Logger.warn("%s prompt needs %d lines, the box holds 2: %s",
      what, lines, tostring(text))
  end
end

-- pokecrystal data/text/common_2.asm ContestStatus: the labels and the
-- "None" placeholder are text, so they go through the catalog like the
-- prompt below.  The caught mon's own name does not: it is a nickname or a
-- species the `pokemon` registry already renames.
-- The cart pins each value to its own column (x=8, 7, 8) because it knows how
-- wide its own labels are.  A translated label can be wider -- "ATTRAPÉ" fills
-- the 7 tiles CAUGHT leaves, "GEFANGEN" and "ATRAPADO" one more -- so the value
-- starts after the label instead of drawing on top of it, keeping the cart's
-- column whenever the label fits.
local function valueColumn(label, cartColumn)
  local labelTiles = math.ceil(Font.width(label) / 8)
  return math.max(cartColumn, 1 + labelTiles + 1)
end

function StartMenu:drawContestStatus()
  Chrome.textbox(0, 0, 17, 5)
  local caught = Strings("CAUGHT")
  local balls = Strings("BALLS:")
  Chrome.print(caught, 1, 1)
  local mon = BugContest.caughtMon(self.save)
  Chrome.print(mon and (mon.nickname or mon.name or mon.species)
    or Strings("None", "contest.caught"), valueColumn(caught, 8), 1)
  if mon then
    local level = Strings("LEVEL")
    Chrome.print(level, 1, 3)
    Chrome.print(tostring(mon.level or 1), valueColumn(level, 7), 3)
  end
  Chrome.print(balls, 1, 5)
  Chrome.print(tostring(BugContest.ballsLeft(self.save)), valueColumn(balls, 8), 5)
end

function StartMenu:draw()
  -- AutomaticGetMenuBottomCoord: bottom = top + 2 * items + 1, so the box is
  -- two rows per entry plus its two border rows.  A menu that a mod has grown
  -- past the screen scrolls instead of overflowing (Chrome.List draws the ▼
  -- hint when there is more below).
  local top = self.contest and 2 or 0
  local height = math.min(#self.items * 2 + 2, Chrome.SCREEN_H - top)
  if self.contest then self:drawContestStatus() end
  Chrome.box(10, top, 10, height)
  self.list:draw()

  if self.phase == "confirmContest" then
    -- pokecrystal data/text/common_2.asm:1381
    Chrome.textbox(0, 12, 18, 4)
    -- One catalog key ("Would you like to" alone has no stable translation
    -- out of context), matching every other confirmation prompt in this
    -- port (src/ui/StartMenu.lua, src/ui/gen2/SaveMenu.lua). Printed via
    -- Chrome.printWrapped, same as InitClock.lua's own call: this box only
    -- has room for two rows (y 14/16, step 2), and printWrapped wraps by
    -- both the translated \n and pixel width, unlike a hand-rolled
    -- \n-only splitter.
    twoRowPrompt(Strings("Would you like to\nend the Contest?"), "contest end")
    -- pokecrystal home/menu.asm:418
    Chrome.box(14, 7, 6, 5)
    Chrome.print(Strings("YES"), 16, 8)
    Chrome.print(Strings("NO"), 16, 10)
    Chrome.cursor(15, self.confirmChoice == 1 and 8 or 10)
    return
  end

  if self.phase == "confirm" then
    Chrome.textbox(0, 12, 18, 4)
    twoRowPrompt(Strings(Strings.source("Return to the\ntitle screen?")),
      "title screen")
    Chrome.box(YESNO_X, YESNO_Y, YESNO_W, YESNO_H)
    Chrome.print(Strings("YES"), YESNO_X + 2, YESNO_Y + 1)
    Chrome.print(Strings("NO"), YESNO_X + 2, YESNO_Y + 3)
    Chrome.cursor(YESNO_X + 1,
      YESNO_Y + (self.confirmChoice == 1 and 1 or 3))
    return
  end

  if not self.showDescription then return end
  local item = self.list:current()
  local desc = item and item.desc
  if not desc then return end
  -- ._DrawMenuAccount ClearBox (0,13) 5 rows by 10, .PrintMenuAccount decoord
  -- 0, 14 and the desc's `next` steps two rows (start_menu.asm:366-382).
  Chrome.paletteFill(0, 13 * 8, 10 * 8, 5 * 8)
  Chrome.print(desc[1] or "", 0, 14)
  Chrome.print(desc[2] or "", 0, 16)
end

StartMenu.ITEMS = ITEMS

return StartMenu
