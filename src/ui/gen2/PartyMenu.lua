-- Gen 2 party list (engine/pokemon/party_menu.asm).
--
-- Six rows plus CANCEL.  Each row is two lines: an animated 16x16 menu icon
-- with the nickname and gender on the first, level and HP bar on the second --
-- the layout Gold uses everywhere it asks "which #MON?", which is why the
-- prompt text is a parameter (.Strings: "Choose a #MON.", "Use on which
-- <PK><MN>?", "Teach which <PK><MN>?", ...).
--
-- Icons come from icons.lua: one 16x32 sheet per ICON_*, two 16x16 frames that
-- alternate roughly twice a second, and MonMenuIcons maps species -> icon.
--
-- Choosing a mon from the FIELD list opens the action submenu (MonSubmenu,
-- engine/pokemon/mon_submenu.asm) rather than answering straight away; every
-- other flavour of the list -- "Use on which <PK><MN>?", "Teach which
-- <PK><MN>?", a battle switch -- goes directly to its caller, which is why
-- the submenu is opt-in through `opts.submenu` and not the default.

local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local Font = require("src.render.Font")
local GbcPalette = require("src.render.GbcPalette")
local HpBar = require("src.battle.gen2.HpBar")
local ItemEffects = require("src.core.gen2.ItemEffects")
local Logger = require("src.core.Logger")
local Mail = require("src.core.gen2.Mail")
local Mon = require("src.battle.gen2.Mon")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")

local PartyMenu = {}
PartyMenu.__index = PartyMenu
PartyMenu.isOpaque = true

-- PartyMenuStrings, verbatim.  <PK>/<MN> are single font glyphs ($e1/$e2) and
-- Font.split matches charmap sequences, so writing them the way the ASM does
-- is both faithful and two tiles narrower than spelling POKéMON out -- which
-- is what keeps "Use on which <PK><MN>?" inside its 18-column text box.
PartyMenu.PROMPTS = {
  choose = "Choose a POKéMON.",
  useItem = "Use on which <PK><MN>?",
  which = "Which <PK><MN>?",
  teach = "Teach which <PK><MN>?",
  moveTo = "Move to where?",
  toWhich = "To which <PK><MN>?",
  none = "You have no <PK><MN>!",
}

-- The icon's two frames swap every 16 logic steps, close to the cart's
-- SPRITE_ANIM cadence.
local ICON_FRAME_STEPS = 16

-- data/mon_menu.asm MonMenuOptions' MONMENU_FIELD_MOVE rows, in table order:
-- a move the mon knows that appears here gets a row of its own above the
-- fixed options, named with GetMoveName rather than a menu string.
PartyMenu.FIELD_MOVES = {
  "CUT", "FLY", "SURF", "STRENGTH", "FLASH", "WATERFALL", "WHIRLPOOL", "DIG",
  "TELEPORT", "SOFTBOILED", "HEADBUTT", "ROCK_SMASH", "MILK_DRINK",
  "SWEET_SCENT",
}

-- MonMenuOptionStrings, in MONMENUVALUE_* order.  GetMonSubmenuItems adds
-- STATS, SWITCH, MOVE and then ITEM (or MAIL, when the held item is mail),
-- and only appends CANCEL while the list is still under NUM_MONMENU_ITEMS.
local NUM_MONMENU_ITEMS = 8

-- MonSubmenu's .MenuHeader is `menu_coords 6, 0, SCREEN_WIDTH - 1,
-- SCREEN_HEIGHT - 1`, and .GetTopCoord then pulls the top edge up to
-- 1 + bottom - 2 * (count + 1) so the box grows downward from a fixed bottom.
local SUBMENU_LEFT = 6
local SUBMENU_RIGHT = 19
local SUBMENU_BOTTOM = 17

-- BattleMonMenu's .MenuHeader is `menu_coords 11, 11, SCREEN_WIDTH - 1,
-- SCREEN_HEIGHT - 1` (engine/pokemon/mon_submenu.asm:277-292).
local BATTLE_SUBMENU_LEFT, BATTLE_SUBMENU_TOP = 11, 11

-- HP bar is 6 tiles wide (48px) in the party list.

local function gridIndex(index, count, direction)
  if count < 1 then return nil end
  local row, col = math.floor((index - 1) / 2), (index - 1) % 2
  if direction == "left" or direction == "right" then
    local other = row * 2 + (1 - col) + 1
    return other <= count and other or index
  end
  local step = direction == "up" and -1 or direction == "down" and 1
  if not step then return nil end
  local rows = math.ceil(count / 2)
  for offset = 1, rows do
    local other = ((row + step * offset) % rows) * 2 + col + 1
    if other <= count then return other end
  end
  return index
end

function PartyMenu:wantsFillScale() return true end
function PartyMenu:drawsWidescreen() return true end

-- opts: party, prompt (key or literal), onChoose(index), onCancel(),
-- icons (icons.lua), palettes (palettes.lua), pokemon (pokemon.lua),
-- submenu (the field MonSubmenu), battleSubmenu (BattleMonMenu)
function PartyMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, PartyMenu)
  self.game = game
  local save = opts.save or (game and game.save)
  -- The MAIL row writes to sPartyMail, which lives on the save rather than on
  -- the mon, so the list keeps the save it was opened over.
  self.save = save
  self.party = opts.party or (save and save.party) or {}
  local data = game and game.data or {}
  -- engine/pokemon/move_mon.asm:1402
  for i = 1, #self.party do
    Mon.refreshStats(self.party[i], data)
  end
  self.icons = opts.icons or data.gen2Icons
  self.palettes = opts.palettes or data.gen2Palettes
  self.pokemon = opts.pokemon or data.pokemon
  self.prompt = PartyMenu.PROMPTS[opts.prompt or "choose"] or opts.prompt
    or PartyMenu.PROMPTS.choose
  -- engine/pokemon/party_menu.asm:297
  self.tmhm = opts.tmhm
  if self.tmhm and (opts.prompt == nil or opts.prompt == "teach") then
    self.prompt = PartyMenu.PROMPTS.teach
  end
  self.onChoose = opts.onChoose
  self.onCancel = opts.onCancel
  self.moves = opts.moves or data.moves
  self.items = opts.items or data.items
  -- PokemonActionSubmenu is only reached from the field list; see the header.
  self.wantsSubmenu = opts.submenu == true
  -- BattleMenu_PKMN's `callfar BattleMonMenu` (engine/battle/core.asm:4810).
  self.wantsBattleSubmenu = opts.battleSubmenu == true
  self.battle = opts.battle == true
  self.submenu = nil
  -- The held slot while SwitchPartyMons' second pick is open; nil otherwise.
  self.switchFrom = nil
  -- wPartyMenuCursor lives ACROSS openings: InitPartyMenuWithCancel /
  -- InitPartyMenuNoCancel seed wMenuCursorY from it and fall back to row 1 only
  -- when it is zero or no longer inside the party (`and a / jr z, .skip / inc b
  -- / cp b / jr c, .done`, engine/pokemon/party_menu.asm:546), so the list -- in
  -- battle and in the field alike -- reopens on the mon last picked.  It is a
  -- WRAM byte, not save data, so it hangs off the game and CleanUpBattleRAM is
  -- what clears it (src/ui/gen2/BattleState.lua's clearMenuCursors).
  local stored = game and game.partyMenuCursor or 0
  self.index = (stored >= 1 and stored <= #self.party) and stored or 1
  self.clock = 0
  self.iconCache = {}
  -- PlacePartyHPBar draws through DrawBattleHPBar, so the party list uses the
  -- battle HUD's tile sheet rather than a bar of its own.
  local BattleHud = require("src.ui.gen2.BattleHud")
  self.hud = BattleHud.new(data.gen2MenuGfx, self.palettes)
  return self
end

function PartyMenu:count()
  -- CANCEL is one past the last mon.  SwitchPartyMons reopens the list
  -- through InitPartyMenuNoCancel, which caps the cursor at the last mon.
  if self.switchFrom then return #self.party end
  return #self.party + 1
end

function PartyMenu:isCancel()
  return self.index > #self.party
end

function PartyMenu:gridNavigation()
  if not self.battle
      or not Runtime.wantsHook("ui.party.grid_navigation") then return false end
  return Runtime.call("ui.party.grid_navigation", function() return false end,
                      self) == true
end

-- ------------------------------------------------------------- mon submenu

-- GetMonSubmenuItems, in its own order: every field move the mon knows first,
-- then STATS, SWITCH, MOVE, and ITEM (MAIL when the held item is mail).
-- CANCEL is appended only while the list is still short of NUM_MONMENU_ITEMS,
-- which is why a mon with five field moves has no CANCEL row and has to be
-- backed out of with B.
--
-- Every PokemonActionSubmenu branch is wired up here: STATS, SWITCH
-- (SwitchPartyMons), the field moves, ITEM (GiveTakePartyMonItem,
-- src/ui/gen2/HeldItemMenu.lua), MAIL (MonMailAction,
-- src/ui/gen2/MailMenu.lua) and MOVE (ManagePokemonMoves, which opens
-- MoveScreenLoop's screen -- src/ui/gen2/SummaryMenu.lua's `moveScreen`).

-- ui.party.submenu identity: an unhooked build hands its own list back.
local function sameItems(_, items) return items end

local function buildSubmenuItems(self, mon)
  -- GetMonSubmenuItems' .egg arm: an EGG offers STATS, SWITCH and CANCEL --
  -- no field moves, no MOVE row, and no ITEM (GiveTakePartyMonItem's first
  -- test is `cp EGG`).
  if mon and mon.isEgg then
    return {
      { id = "STATS", label = "STATS" },
      { id = "SWITCH", label = "SWITCH" },
      { id = "CANCEL", label = "CANCEL" },
    }
  end
  local items = {}
  local known = {}
  for _, entry in ipairs((mon and mon.moves) or {}) do
    if entry.id then known[entry.id] = entry end
  end
  for _, id in ipairs(PartyMenu.FIELD_MOVES) do
    if known[id] then
      local def = self.moves and self.moves[id]
      items[#items + 1] = {
        id = id, label = (def and def.name) or id, fieldMove = true,
      }
    end
  end
  items[#items + 1] = { id = "STATS", label = "STATS" }
  items[#items + 1] = { id = "SWITCH", label = "SWITCH" }
  items[#items + 1] = { id = "MOVE", label = "MOVE" }
  -- ItemIsMail, not a pocket test: mail lives in the ordinary ITEM pocket
  -- (ItemAttributes gives FLOWER_MAIL pocketId 1), so the only thing that
  -- says "this is mail" is data/items/mail_items.asm's own list.
  local isMail = Mail.monHoldsMail(mon)
  items[#items + 1] = isMail and { id = "MAIL", label = "MAIL" }
    or { id = "ITEM", label = "ITEM" }
  if #items < NUM_MONMENU_ITEMS then
    items[#items + 1] = { id = "CANCEL", label = "CANCEL" }
  end
  return items
end

-- BattleMonMenu's .MenuData: three rows, SWITCH first
-- (engine/pokemon/mon_submenu.asm:286-292).
local function buildBattleSubmenuItems()
  return {
    { id = "SWITCH", label = "SWITCH" },
    { id = "STATS", label = "STATS" },
    { id = "CANCEL", label = "CANCEL" },
  }
end

-- The assembled list runs through ui.party.submenu -- the same hook name and
-- the same (game, items, mon, ctx) payload the Gen 1 site uses
-- (src/ui/PartyMenu.lua) -- so one mod source can add, drop or reorder rows on
-- both generations.  Gold's MAIL row and its field moves are simply entries in
-- the list the hook receives; they need no name of their own.
--
-- ctx.battle marks the BattleMonMenu list (engine/pokemon/mon_submenu.asm:247),
-- the SWITCH/STATS/CANCEL box BattleMenu_PKMN opens over the battle party list;
-- it is false for PokemonActionSubmenu, the FIELD list (see the header).
-- ctx.overworld is Gold's World, the Gen 1 key's counterpart.
function PartyMenu:submenuItems(mon)
  local battle = self.wantsBattleSubmenu == true
  local items = battle and buildBattleSubmenuItems()
    or buildSubmenuItems(self, mon)
  local ctx = { battle = battle, overworld = self.game and self.game.world }
  local hooked = Runtime.call("ui.party.submenu", sameItems,
                              self.game, items, mon, ctx)
  if type(hooked) == "table" then return hooked end
  Logger.error("ui.party.submenu returned %s; keeping the vanilla list",
               type(hooked))
  return items
end

-- .GetTopCoord: top = 1 + bottom - 2 * (count + 1).  PopulateMonMenu then
-- starts writing at MenuBoxCoord2Tile + 2 * SCREEN_WIDTH + 2, so the labels
-- are two rows and two columns inside the box's top-left corner and step two
-- rows each -- the cursor sits one column left of them, at left + 1.
function PartyMenu.submenuTop(count)
  return 1 + SUBMENU_BOTTOM - 2 * (count + 1)
end

function PartyMenu.submenuLabelCoord(count, row)
  return SUBMENU_LEFT + 2, PartyMenu.submenuTop(count) + 2 + (row - 1) * 2
end

function PartyMenu:openSubmenu()
  local mon = self.party[self.index]
  if not mon then return end
  self.submenu = { items = self:submenuItems(mon), index = 1, mon = mon,
    slot = self.index, battle = self.wantsBattleSubmenu or nil }
end

function PartyMenu:closeSubmenu()
  self.submenu = nil
end

-- SwitchPartyMons (engine/pokemon/mon_menu.asm).  `cp 2 / jr c, .DontSwitch`:
-- one mon is nothing to switch with, and the row backs out the way
-- CancelPokemonAction does.  Otherwise the list reopens through
-- InitPartyMenuNoCancel in PARTYMENUACTION_MOVE dress -- "Move to where?",
-- a '▷' parked on the held row -- and PartyMenuSelect picks the other end.
function PartyMenu:beginSwitch(slot)
  if #self.party < 2 then return end
  self.switchFrom = slot
end

-- _SwitchPartyMons (engine/pokemon/switchpartymons.asm): the two party
-- structs swap whole (nickname and OT ride inside the port's mon record), and
-- the sPartyMail structs are copied across with them -- Mail.swapSlots is
-- that CopyBytes pair.  Picking the held slot again is the `.skip` arm:
-- nothing moves.
function PartyMenu:finishSwitch()
  local from, to = self.switchFrom, self.index
  self.switchFrom = nil
  if not (from and to) or from == to then return end
  local party = self.party
  party[from], party[to] = party[to], party[from]
  -- sPartyMail is keyed by party slot on the save; a list opened over some
  -- other table (a battle copy, a day-care pick) has no mail to carry.
  if self.save and self.save.party == party then
    Mail.swapSlots(self.save, from, to)
  end
  -- engine/pokemon/switchpartymons.asm:38
  local data = self.game and self.game.data
  local ok, Sound = pcall(require, "src.core.Sound")
  if not (ok and data and Sound and Sound.play) then return end
  local sfx = data.audio and data.audio.sfx
  if sfx and sfx[Sound.resolve(data, "Sfx_SwitchPokemon")] then
    pcall(Sound.play, data, "Sfx_SwitchPokemon")
  end
end

-- The reopened list: InitPartyMenuNoCancel caps the cursor at the last mon,
-- and PartyMenuSelect reads only A (hand both slots to _SwitchPartyMons) and
-- B (the .DontSwitch arm -- back to the ordinary list, nothing moved).
function PartyMenu:updateSwitch(input)
  local total = #self.party
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or total
  elseif input:wasPressed("down") then
    self.index = self.index < total and self.index + 1 or 1
  elseif input:wasPressed("b") then
    self.switchFrom = nil
  elseif input:wasPressed("a") then
    self:finishSwitch()
  end
end

-- OpenPartyStats (engine/pokemon/mon_menu.asm): wMonType is cleared to
-- PARTYMON, the volume is dropped for the cry, and StatsScreenInit runs over
-- the party list -- so the summary is pushed on top rather than replacing it,
-- and closing it lands back on the same row.
function PartyMenu:openStats()
  local stack = self.game and self.game.stack
  if not stack then return end
  Screens.push(self.game, "Gen2SummaryMenu", {
    party = self.party,
    index = self.index,
    onClose = function() stack:pop() end,
  })
end

-- MonMenu_Cut and its thirteen siblings (engine/pokemon/mon_menu.asm) are one
-- routine each and all the same shape: farcall the move's *Function, then read
-- wFieldMoveSucceeded.  $1 returns $2 from PokemonActionSubmenu, which closes
-- the party list AND the START menu behind it so the script the function
-- queued can run in the overworld; anything else returns $3 and redraws the
-- list where it was, with the refusal already printed over it by
-- MenuTextboxBackup.
--
-- The refusal text and the queueing both live in the world
-- (src/world/gen2/FieldMoves.lua and World:useFieldMove), because a field move
-- is a question about the map, not about the menu.  All that is left here is
-- the $2 / $3 branch.
function PartyMenu:useFieldMove(moveId, mon)
  local world = self.game and self.game.world
  if not (world and world.useFieldMove) then return end
  local result = world:useFieldMove(moveId, mon)
  if result and result.ok then self:exitToField() end
end

-- ManagePokemonMoves (engine/pokemon/mon_menu.asm:858-873), the MOVE row: an
-- EGG returns at once (`cp EGG / jr z, .egg`), and every other mon gets
-- MoveScreenLoop -- the move list with its descriptions, and A to lift a move
-- and drop it on another row.  The screen clears the tilemap for itself
-- (SetUpMoveScreenBG), so it is pushed on top rather than replacing this list.
--
-- MoveScreenLoop opens with `ld a, [wCurPartyMon] / inc a / ld
-- [wPartyMenuCursor], a` and does it again on every left/right cycle, so the
-- slot it was last showing is the row this list comes back on.
function PartyMenu:openMoveManager(slot, mon)
  local game = self.game
  if not (game and game.stack) then return end
  if mon and mon.isEgg then return end
  local screen
  screen = Screens.push(game, "Gen2SummaryMenu", {
    party = self.party,
    index = slot,
    moveScreen = true,
    onClose = function()
      game.stack:pop()
      local landed = screen and screen.index or slot
      self.index = math.max(1, math.min(landed, #self.party))
      self:storeCursor()
    end,
  })
end

-- GiveTakePartyMonItem, the ITEM row.  Its own menu is drawn over this list
-- (menu_coords 12, 12, 19, 17), so it is a non-opaque state too.  An EGG never
-- reaches it: `cp EGG / jr z, .cancel` is the routine's first test.
function PartyMenu:openHeldItemMenu(slot, mon)
  local game = self.game
  if not (game and game.stack and self.save) then return end
  if mon and mon.isEgg then return end
  Screens.push(game, "Gen2HeldItemMenu", {
    save = self.save,
    slot = slot,
    items = self.items,
    onClose = function() game.stack:pop() end,
  })
end

-- MonMailAction (engine/pokemon/mon_menu.asm), the MAIL row.  The READ / TAKE
-- / QUIT menu is drawn OVER this list (MENU_BACKUP_TILES at menu_coords 9, 10,
-- 19, 17), so it is a non-opaque state pushed on top rather than a submenu of
-- this screen's own.
function PartyMenu:openMailMenu(slot)
  local game = self.game
  if not (game and game.stack and self.save) then return end
  Screens.push(game, "Gen2MailMenu", {
    save = self.save,
    slot = slot,
    onClose = function() game.stack:pop() end,
  })
end

-- The $2 return.  Same exit PackMenu's PACKSTATE_QUITRUNSCRIPT takes, for the
-- same reason: only an empty stack lets the overworld run the queued script.
function PartyMenu:exitToField()
  local stack = self.game and self.game.stack
  if stack and stack.clear then
    stack:clear()
  elseif self.onCancel then
    self.onCancel()
  end
end

-- The ids updateSubmenu dispatches itself; anything else is a mod's row.
local VANILLA_SUBMENU_IDS = {
  STATS = true, SWITCH = true, MAIL = true, ITEM = true, MOVE = true,
  CANCEL = true,
}

-- MonMenuLoop: A selects, B is MONMENUITEM_CANCEL, and nothing else is read.
function PartyMenu:updateSubmenu(input)
  local menu = self.submenu
  local total = #menu.items
  if input:wasPressed("up") then
    menu.index = menu.index > 1 and menu.index - 1 or total
  elseif input:wasPressed("down") then
    menu.index = menu.index < total and menu.index + 1 or 1
  elseif input:wasPressed("b") then
    self:closeSubmenu()
  elseif input:wasPressed("a") then
    local item = menu.items[menu.index]
    local mon = menu.mon
    local slot = menu.slot or self.index
    local battle = menu.battle
    self:closeSubmenu()
    if not item then return end
    -- `cp $1 ; SWITCH / jp z, TryPlayerSwitch` and `.Cancel: jp BattleMenu`
    -- (engine/battle/core.asm:4811-4816).
    if battle and item.id == "SWITCH" then
      if self.onChoose then self.onChoose(slot, mon) end
      return
    elseif battle and item.id == "CANCEL" then
      if self.onCancel then self.onCancel() end
      return
    end
    -- A hook-injected entry carries a callback instead of one of the ids this
    -- chain knows, and it is answered first for the reason the Gen 1 site
    -- answers it first (src/ui/PartyMenu.lua:346): a mod cannot mint new ids
    -- into the chain, so without the arm its row draws and does nothing.
    if item.onSelect and not VANILLA_SUBMENU_IDS[item.id] and not item.fieldMove then
      item.onSelect(mon, self.game)
    elseif item.id == "STATS" then
      self:openStats()
    elseif item.id == "SWITCH" then
      self:beginSwitch(slot)
    elseif item.id == "MAIL" then
      self:openMailMenu(slot)
    elseif item.id == "ITEM" then
      self:openHeldItemMenu(slot, mon)
    elseif item.id == "MOVE" then
      self:openMoveManager(slot, mon)
    elseif item.fieldMove then
      self:useFieldMove(item.id, mon)
    end
  end
end

function PartyMenu:update(_dt)
  self.clock = self.clock + 1
  local input = self.game and self.game.input
  if not input then return end
  if self.submenu then
    self:updateSubmenu(input)
    return
  end
  if self.switchFrom then
    self:updateSwitch(input)
    return
  end
  local total = self:count()
  local grid
  if self:gridNavigation() then
    local direction = input:wasPressed("left") and "left"
      or input:wasPressed("right") and "right"
      or input:wasPressed("up") and "up"
      or input:wasPressed("down") and "down"
    grid = gridIndex(self.index, #self.party, direction)
  end
  if grid then
    self.index = grid
    self:storeCursor()
  elseif input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or total
  elseif input:wasPressed("down") then
    self.index = self.index < total and self.index + 1 or 1
  elseif input:wasPressed("a") then
    self:storeCursor()
    if self:isCancel() then
      if self.onCancel then self.onCancel() end
    elseif self.wantsSubmenu or self.wantsBattleSubmenu then
      self:openSubmenu()
    elseif self.onChoose then
      local mon = self.party[self.index]
      if self.tmhm and mon and mon.isEgg then
        -- engine/items/tmhm.asm:104
        local world = self.game and self.game.world
        if world and world.playSfxNamed then world:playSfxNamed("Sfx_Wrong") end
        return
      end
      self.onChoose(self.index, mon)
    end
  elseif input:wasPressed("b") then
    self:storeCursor()
    if self.onCancel then self.onCancel() end
  end
end

-- PartyMenuSelect's `ld [wPartyMenuCursor], a` sits after the CANCEL test but
-- BEFORE the B-button test (engine/pokemon/party_menu.asm:600), so backing out
-- of a mon's row still records it and only the CANCEL row leaves the byte
-- alone.  1-based over the party, the same numbering PartyMenu:count() uses.
function PartyMenu:storeCursor()
  local game = self.game
  if not game or self:isCancel() then return end
  game.partyMenuCursor = self.index
end

-- ReadMonMenuIcon (engine/gfx/mon_icons.asm): an EGG slot draws ICON_EGG --
-- the `cp EGG / jr z, .egg` arm -- and any other species reads MonMenuIcons.
function PartyMenu:iconIdFor(mon)
  if not mon then return nil end
  if mon.isEgg then return "ICON_EGG" end
  return self.icons and self.icons.species and mon.species
    and self.icons.species[mon.species] or nil
end

-- The icon image for a mon, plus which 16x16 frame to show.
--
-- The path goes out through pokemon.icon before it is loaded -- the SAME hook
-- name, the same (data, mon, vanillaPath, { name = iconId }) call and the same
-- ctx the Gen 1 party list makes (src/ui/PartyMenu.lua:186 through
-- src/pokemon/Sprites.lua iconPath), so one skin mod repaints the party icons
-- in both games.  Sprites.iconPath does its own Runtime.wantsHook check and
-- hands the vanilla path straight back on an unhooked boot, so this costs a
-- table lookup per row; the cache is keyed on the RESOLVED path so a mod's
-- image does not ride the built-in's entry.
function PartyMenu:iconFor(mon)
  local iconId = self:iconIdFor(mon)
  local entry = iconId and self.icons and self.icons.icons
    and self.icons.icons[iconId]
  local path = entry and entry.image
  path = require("src.pokemon.Sprites").iconPath(
    self.game and self.game.data, mon, path, { name = iconId })
  if not path then return nil end
  local cached = self.iconCache[path]
  if cached == nil then
    local ok, img = pcall(Assets.image, path)
    cached = ok and img or false
    self.iconCache[path] = cached
  end
  if not cached then return nil end
  local frame = math.floor(self.clock / ICON_FRAME_STEPS) % 2
  return cached, frame
end

-- .SpawnItemIcon (engine/gfx/mon_icons.asm): a mon carrying something does not
-- get a word of text, it gets its ICON's bottom-left tile swapped.  A zero
-- MON_ITEM returns early; otherwise ItemIsMail picks
-- SPRITE_ANIM_FRAMESET_PARTY_MON_WITH_MAIL over ..._WITH_ITEM.  Returns the row
-- of the HeldItemIcons sheet to draw -- 0 is mail.2bpp, 1 is item.2bpp, the
-- order the two tiles are INCBIN'd in -- or nil for an empty hand.  There is
-- deliberately no EGG arm: the cart has none, because an egg's item byte is
-- always zero (Breeding.hatchEgg/DayCare_GiveEgg never write one).
function PartyMenu.heldMarkerRow(mon)
  if type(mon) ~= "table" then return nil end
  local item = mon.item
  if item == nil or item == 0 or item == "" then return nil end
  return Mail.monHoldsMail(mon) and 0 or 1
end

-- The HeldItemIcons sheet, which GetIconGFX uploads as the two tiles straight
-- after an icon's eight (`ld de, 8 tiles / add hl, de`), so it rides the same
-- cache entry as the icons themselves.  A cache built before the extractor read
-- the symbol simply has no `heldItem` row: the marker goes undrawn and the list
-- looks exactly as it did, rather than erroring on a missing image.
function PartyMenu:heldMarkerImage()
  local entry = self.icons and self.icons.heldItem
  if not (entry and entry.image) then return nil end
  local cached = self.iconCache[entry.image]
  if cached == nil then
    local ok, img = pcall(Assets.image, entry.image)
    cached = ok and img or false
    self.iconCache[entry.image] = cached
  end
  return cached or nil
end

-- AnimSeq_PartyMon rewrites the icon's x every frame: an unselected row sits at
-- 8 * 2 and the highlighted one at 8 * 3, so the icons rest against the left
-- wall and the one under the cursor slides a tile right to make room for it.
-- Screen x is the struct's x minus 16 (the OAM template's -1 tile, then the
-- hardware's -8), which is 0 and 8.
function PartyMenu:iconX(index)
  return index == self.index and 8 or 0
end

-- ...and AnimSeq_PartyMonSwitch bobs that one: VAR1 counts frames and, every
-- sixteenth, bit 4 decides whether YOFFSET is 0 or negative.  So the selected
-- icon rides two pixels high for half of each 32-frame cycle.
function PartyMenu:iconBob(index)
  if index ~= self.index then return 0 end
  return (math.floor(self.clock / 16) % 2 == 1) and -2 or 0
end

function PartyMenu:drawIcon(mon, px, py)
  local image, frame = self:iconFor(mon)
  if not image then return end
  local G = love.graphics
  local iw, ih = image:getDimensions()
  local markerRow = PartyMenu.heldMarkerRow(mon)
  local marker = markerRow and self:heldMarkerImage() or nil
  local paint
  if marker then
    -- The _WITH_ITEM / _WITH_MAIL OAM sets (data/sprite_anims/oam.asm) are the
    -- ordinary four quadrants with the `dbsprite -1, 0` entry -- the bottom
    -- left -- reading tile $08/$09 instead of the icon's own.  So three of the
    -- icon's 8x8 tiles are drawn and the fourth is REPLACED, not covered: the
    -- marker tile is transparent in places and the icon would show through it.
    -- Both of the frameset's oamframes name the same marker tile, so it must
    -- not be indexed by `frame`: the icon bobs, the marker does not.
    local mw, mh = marker:getDimensions()
    local topLeft = G.newQuad(0, frame * 16, 8, 8, iw, ih)
    local topRight = G.newQuad(8, frame * 16, 8, 8, iw, ih)
    local bottomRight = G.newQuad(8, frame * 16 + 8, 8, 8, iw, ih)
    local held = G.newQuad(0, markerRow * 8, 8, 8, mw, mh)
    paint = function()
      G.draw(image, topLeft, px, py)
      G.draw(image, topRight, px + 8, py)
      G.draw(image, bottomRight, px + 8, py + 8)
      G.draw(marker, held, px, py + 8)
    end
  else
    local quad = G.newQuad(0, frame * 16, 16, 16, iw, ih)
    paint = function() G.draw(image, quad, px, py) end
  end
  G.setColor(1, 1, 1, 1)
  -- Every party icon OAM entry is PAL_OW_RED (data/sprite_anims/oam.asm:315-355)
  -- and InitPartyMenuOBPals loads PartyMenuOBPals into OBJ 0 for the whole list,
  -- species and EGG alike (engine/gfx/color.asm:593-598, :1228-1229).
  local pals = self.palettes and self.palettes.partyMenu
  local colors = pals and pals[1] or nil
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, paint)
  else
    paint()
  end
end

-- PlacePartyHPBar calls DrawBattleHPBar (home/pokemon.asm) with `ld d, $6`, and
-- that routine lays the WHOLE assembly, not just the bar: "HP:" is $60/$61 at
-- the coordinate it is given, then six $62 bar cells, then the $6b end cap.  So
-- a party row's bar is the battle HUD's bar, tile for tile -- which is why this
-- goes through BattleHud instead of drawing a rectangle.
function PartyMenu:drawHpBar(mon, tx, ty)
  local maxHp = mon.maxHp or (mon.stats and mon.stats.hp)
  if self.hud and self.hud:available() then
    return self.hud:drawHpBar(mon.hp, maxHp, tx, ty)
  end
  -- No battle-HUD sheet in the cache: the plain bar, two tiles in, so the
  -- fallback still lands where the cells would.
  HpBar.draw(self.palettes, mon.hp, maxHp, (tx + 2) * 8, ty * 8 + 2)
  return tx + 2 + HpBar.LENGTH_TILES
end

-- PrintNum with `lb bc, 2, 3`: three columns, space-padded from the right.
local function num3(value)
  local text = tostring(math.max(0, math.floor(value or 0)))
  if #text > 3 then text = text:sub(-3) end
  return (" "):rep(3 - #text) .. text
end

-- PlaceStatusString (engine/pokemon/mon_stats.asm): three letters, and a mon
-- with no HP reads FNT whatever its status byte says.
local function statusString(mon)
  if (mon.hp or 0) <= 0 then return "FNT" end
  local status = mon.status
  if not status then return nil end
  local class = ItemEffects.STATUS_CLASS[tostring(status):lower()]
  return class and class:upper()
end

-- One list row's strings, exactly what WritePartyMenuTilemap's quality
-- routines write.  Every routine but PlacePartyNicknames begins with
-- PartyMenuCheckEgg (`cp EGG`) and skips its row for an egg, so an egg is a
-- name and an icon alone: no HP digits, no bar, no level, no FNT.  The name
-- itself is String_Egg -- GiveEgg writes "EGG" over the nickname slot -- so
-- it never reads as the species hiding inside.
function PartyMenu.rowFor(mon)
  if mon.isEgg then return { name = "EGG" } end
  local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 0
  return {
    name = mon.nickname or mon.name or mon.species or "?",
    hp = num3(mon.hp) .. "/" .. num3(maxHp),
    status = statusString(mon),
    -- <LV> is one font glyph ($6e), not the two characters ":L".
    level = "<LV>" .. tostring(mon.level or 1),
  }
end

-- engine/pokemon/party_menu.asm:331
function PartyMenu:tmhmAble(mon)
  if not mon or mon.isEgg then return nil end
  local move = self.tmhm and self.tmhm.move
  if not move then return nil end
  local species = self.pokemon and self.pokemon[mon.species]
  for _, id in ipairs((species and species.tmhm) or {}) do
    if id == move then return "ABLE" end
  end
  return "NOT ABLE"
end

-- WritePartyMenuTilemap, jumptable entry by jumptable entry.  Every coordinate
-- below is the hlcoord the matching PARTYMENUQUALITY_* routine uses, and each
-- steps 2 * SCREEN_WIDTH per mon:
--
--   PlacePartyNicknames        (3, 1)   CANCEL two columns left of the row
--                                       after the last mon
--   PlacePartyMenuHPDigits     (13,1)   "%3d" "/" "%3d"
--   PlacePartyMonStatus        (5, 2)
--   PlacePartyMonLevel         (8, 2)   <LV> then a left-aligned number
--   PlacePartyHPBar            (11,2)   DrawBattleHPBar: "HP:" + 6 cells + cap
--   PartyMenu_InitAnimatedMonIcon      sprite anim at y $1c + $10 * i;
--                                      .OAMData_RedWalk's first entry is
--                                      dbsprite -1,-1, so the icon's top-left
--                                      OAM is (x - 8, y - 8) and, minus the
--                                      (8,16) hardware offset, pixel
--                                      (x - 16, 4 + 16 * i)
--   PartyMenu2DMenuData        cursor at column 0, rows 1, 3, 5 ...
--   PlacePartyMenuText         Textbox at (0,14) 18x2 interior, string at (1,16)
function PartyMenu:drawPanel()
  -- LoadPartyMenuGFX starts with LoadFontsBattleExtra, so tiles $60-$6f on this
  -- screen are FontBattleExtra's: <LV> ($6e) is the bold ":L" here, not
  -- FontExtra's "Lv", and the HP bar's cells come from the same sheet.
  local wasBattle = Font.useBattleExtra(true)
  Chrome.clear()

  for i, mon in ipairs(self.party) do
    local nameY = 1 + (i - 1) * 2
    local dataY = nameY + 1
    if i == self.index then
      Chrome.cursor(0, nameY)
    elseif self.switchFrom == i then
      -- SwitchPartyMons parks '▷' on the held row (`ld [hl], '▷'`); the live
      -- cursor overwrites it whenever it sits there.
      Chrome.cursor(0, nameY, true)
    end
    self:drawIcon(mon, self:iconX(i), 4 + (i - 1) * 16 + self:iconBob(i))
    local row = PartyMenu.rowFor(mon)
    Chrome.print(row.name, 3, nameY)
    if self.tmhm then
      local able = self:tmhmAble(mon)
      if able then Chrome.print(able, 12, dataY) end
    else
      if row.hp then Chrome.print(row.hp, 13, nameY) end
      if row.hp then self:drawHpBar(mon, 11, dataY) end
    end
    if row.status then Chrome.print(row.status, 5, dataY) end
    if row.level then Chrome.print(row.level, 8, dataY) end
  end

  -- .end does `dec hl` twice from the row past the last nickname, so CANCEL
  -- starts two columns left of where the nicknames do.
  local cancelY = 1 + #self.party * 2
  if self:isCancel() then Chrome.cursor(0, cancelY) end
  Chrome.print("CANCEL", 1, cancelY)

  -- PlacePartyMenuText: Textbox at (0,14) with a 2x18 interior, string at (1,16).
  -- ReturnToMapWithSpeechTextbox restores the normal font afterwards, and so
  -- does this: the prompt is ordinary text.
  Font.useBattleExtra(wasBattle)
  Chrome.box(0, 14, 20, 4)
  -- SwitchPartyMons swaps the prompt for PARTYMENUACTION_MOVE's string while
  -- the second pick is open, then puts the caller's own back.
  local prompt = self.switchFrom and PartyMenu.PROMPTS.moveTo or self.prompt
  Chrome.print(#self.party == 0 and PartyMenu.PROMPTS.none or prompt, 1, 16)
  -- PokemonActionSubmenu clears (1,15) 2x18 before MonSubmenu draws, so the
  -- prompt is gone behind the box rather than showing through it.
  if self.submenu then self:drawSubmenu() end
  love.graphics.setColor(1, 1, 1, 1)
end

-- MenuBox over the bottom right of the list, with the labels two rows and two
-- columns inside it and the cursor one column left of them.
function PartyMenu:drawSubmenu()
  local menu = self.submenu
  -- GetMenuTextStartCoord puts the labels at (13, 12) two rows apart, cursor
  -- one column left (home/menu.asm:199-226).
  if menu.battle then
    Chrome.box(BATTLE_SUBMENU_LEFT, BATTLE_SUBMENU_TOP, 9, 7)
    for row, item in ipairs(menu.items) do
      local ty = BATTLE_SUBMENU_TOP + 1 + (row - 1) * 2
      if row == menu.index then Chrome.cursor(BATTLE_SUBMENU_LEFT + 1, ty) end
      Chrome.print(item.label, BATTLE_SUBMENU_LEFT + 2, ty)
    end
    return
  end
  local count = #menu.items
  local top = PartyMenu.submenuTop(count)
  Chrome.box(SUBMENU_LEFT, top, SUBMENU_RIGHT - SUBMENU_LEFT + 1,
    SUBMENU_BOTTOM - top + 1)
  for row, item in ipairs(menu.items) do
    local tx, ty = PartyMenu.submenuLabelCoord(count, row)
    if row == menu.index then Chrome.cursor(tx - 1, ty) end
    Chrome.print(item.label, tx, ty)
  end
end

function PartyMenu:draw()
  self:drawPanel()
end

function PartyMenu:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(math.floor((winW - 160 * scale) / 2),
    math.floor((winH - 144 * scale) / 2))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

return PartyMenu
