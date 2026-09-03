-- The party list's field behaviour: SwitchPartyMons (engine/pokemon/
-- mon_menu.asm + engine/pokemon/switchpartymons.asm) and the EGG rules
-- (engine/pokemon/party_menu.asm PartyMenuCheckEgg, engine/pokemon/
-- mon_submenu.asm GetMonSubmenuItems .egg, engine/pokemon/stats_screen.asm
-- EggStatsScreen).
--
-- ROM-free and draw-free, the same shape as tests/gen2_summary_test.lua: the
-- list's rows and the egg summary's page are built as data before anything is
-- drawn, so the suite asserts the data and drives the input loops with a stub
-- pad.  What a test cannot say -- whether the screens LOOK right -- is what
-- tests/drivers/gold_party_submenu.lua exists for.

package.path = "./?.lua;" .. package.path

-- The UI modules require love-side helpers at load time.  Stub the pieces they
-- touch during construction and logic; nothing here draws.
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

-- StatsScreen_PlaceFrontpic ends in PlayMonCry; count the calls so the egg's
-- silence is an assertion rather than a hope.
local cries = 0
package.loaded["src.core.Sound"] = package.loaded["src.core.Sound"] or {}
package.loaded["src.core.Sound"].playCry = function() cries = cries + 1 end

local Mail = require("src.core.gen2.Mail")
local Mon = require("src.battle.gen2.Mon")
local PartyMenu = require("src.ui.gen2.PartyMenu")
local SummaryMenu = require("src.ui.gen2.SummaryMenu")
local Gen2Battle = require("src.battle.gen2.Battle")
local Registry = require("src.mods.Registry")
local Schemas = require("src.mods.Schemas")
local Strings = require("src.core.Strings")

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

-- ------------------------------------------------------------- fixture data

local DATA = {
  pokemon = {
    growthRates = {
      GROWTH_MEDIUM_SLOW = {
        numerator = 6, denominator = 5, squared = -15, linear = 100,
        constant = 140,
      },
    },
    CYNDAQUIL = {
      id = "CYNDAQUIL", name = "CYNDAQUIL", dex = 155, index = 155,
      growthRate = "GROWTH_MEDIUM_SLOW",
      types = { "FIRE", "FIRE" },
      baseStats = {
        hp = 39, attack = 52, defense = 43, speed = 65,
        specialAttack = 60, specialDefense = 50,
      },
    },
    TOTODILE = {
      id = "TOTODILE", name = "TOTODILE", dex = 158, index = 158,
      growthRate = "GROWTH_MEDIUM_SLOW",
      types = { "WATER", "WATER" },
      baseStats = {
        hp = 50, attack = 65, defense = 64, speed = 43,
        specialAttack = 44, specialDefense = 48,
      },
    },
    TOGEPI = {
      id = "TOGEPI", name = "TOGEPI", dex = 175, index = 175,
      growthRate = "GROWTH_MEDIUM_SLOW",
      types = { "NORMAL", "NORMAL" },
      eggSteps = 20,
      baseStats = {
        hp = 35, attack = 20, defense = 65, speed = 20,
        specialAttack = 40, specialDefense = 65,
      },
    },
  },
  moves = {
    TACKLE = { id = "TACKLE", name = "TACKLE", pp = 35 },
    SURF = { id = "SURF", name = "SURF", pp = 15 },
  },
  items = {
    BERRY = { id = "BERRY", name = "BERRY", pocket = "ITEM" },
    FLOWER_MAIL = { id = "FLOWER_MAIL", name = "FLOWER MAIL",
      pocket = "ITEM" },
  },
  gen2MenuGfx = {},
  -- A cut-down icons.lua: enough for iconIdFor's two arms.
  gen2Icons = {
    species = { CYNDAQUIL = "ICON_FOX", TOTODILE = "ICON_MONSTER",
      TOGEPI = "ICON_MONSTER" },
    icons = {
      ICON_FOX = { id = "ICON_FOX", image = "x/fox.png" },
      ICON_MONSTER = { id = "ICON_MONSTER", image = "x/monster.png" },
      ICON_EGG = { id = "ICON_EGG", image = "x/egg.png" },
    },
  },
}

local function mergedGen2Statuses()
  local registry = Registry.new("statuses", Schemas.REGISTRIES.statuses)
  registry.base = function() return Gen2Battle.STATUSES end
  registry:patch("poison", { hudLabel = "TOX" }, "translation")
  local merged = {}
  for id in pairs(Gen2Battle.STATUSES) do merged[id] = registry:get(id) end
  return merged, registry
end

local function newGame(save)
  return {
    input = newInput(),
    save = save,
    data = DATA,
    stack = { _items = {},
      push = function(self, s) self._items[#self._items + 1] = s end,
      pop = function(self) return table.remove(self._items) end,
      top = function(self) return self._items[#self._items] end,
    },
  }
end

local function mon(species, level, opts)
  opts = opts or {}
  local built = Mon.new(DATA, species, level, {
    dvs = { attack = 15, defense = 15, speed = 15, special = 15 },
    moves = opts.moves,
  })
  for key, value in pairs(opts.fields or {}) do built[key] = value end
  return built
end

-- The shape GiveEgg (engine/pokemon/move_mon.asm) leaves in the slot: the
-- real species under an isEgg mark, "EGG" for a nickname on the day-care
-- path but NOT on the giveegg one, the counter in cycles, and zero HP.
local function egg(cycles)
  local built = mon("TOGEPI", 5)
  built.isEgg = true
  built.eggSteps = cycles or 20
  built.hp = 0
  return built
end

local function newSave()
  return {
    player = { name = "GOLD", id = 12345 },
    party = {
      mon("CYNDAQUIL", 12, {
        moves = { { id = "TACKLE", pp = 30, maxPp = 35 } },
        fields = { nickname = "CYNDAQUIL", item = "BERRY" },
      }),
      mon("TOTODILE", 10, {
        moves = { { id = "SURF", pp = 15, maxPp = 15 } },
        fields = { nickname = "TOTODILE" },
      }),
    },
  }
end

-- ----------------------------------------------------------- the list rows

-- WritePartyMenuTilemap's quality routines, as row data.
local save = newSave()
local row = PartyMenu.rowFor(save.party[1])
check("a mon's row shows its nickname", row.name, "CYNDAQUIL")
check("and its HP digits", row.hp ~= nil, true)
check("and its level", row.level, "<LV>12")
check("a healthy mon has no status", row.status, nil)

local fnt = mon("TOTODILE", 10, { fields = { hp = 0 } })
check("a fainted mon reads FNT", PartyMenu.rowFor(fnt).status, "FNT")

local poisoned = mon("TOTODILE", 10, { fields = { status = "poison" } })
DATA.gen2Statuses = mergedGen2Statuses()
check("a status registry translation reaches a Gen 2 party row",
  PartyMenu.rowFor(poisoned, nil, DATA.gen2Statuses).status, "TOX")
DATA.gen2Statuses = nil

-- PartyMenuCheckEgg: every quality routine skips an EGG's row, and the name
-- is String_Egg -- never the species hiding inside.
local eggRow = PartyMenu.rowFor(egg())
check("an egg's row reads EGG", eggRow.name, "EGG")
check("an egg has no HP digits", eggRow.hp, nil)
check("an egg has no level", eggRow.level, nil)
check("an egg is not FNT", eggRow.status, nil)

-- ReadMonMenuIcon: MonMenuIcons for a species, ICON_EGG for an egg.
local game = newGame(save)
local party = PartyMenu.new(game, { party = save.party, submenu = true })
check("a species icon reads MonMenuIcons",
  party:iconIdFor(save.party[1]), "ICON_FOX")
check("an egg draws ICON_EGG", party:iconIdFor(egg()), "ICON_EGG")

-- ------------------------------------------------------------- egg submenu

-- GetMonSubmenuItems' .egg arm: STATS, SWITCH, CANCEL and nothing else.
local eggItems = party:submenuItems(egg())
check("an egg's submenu has three rows", #eggItems, 3)
check("STATS first", eggItems[1].id, "STATS")
check("SWITCH second", eggItems[2].id, "SWITCH")
check("CANCEL third", eggItems[3].id, "CANCEL")

Strings.load({ strings = {
  STATS = "STATS FR", SWITCH = "ÉCHANGER", MOVE = "DÉPLACER",
  ITEM = "OBJET", MAIL = "COURRIER", CANCEL = "ANNULER",
  FNT = "K.O.", EGG = "ŒUF", ABLE = "APTE", ["NOT ABLE"] = "INAPTE",
} })
local translatedItems = party:submenuItems(save.party[1])
check("the submenu keeps a stable STATS id", translatedItems[1].id, "STATS")
check("and translates the STATS label", translatedItems[1].label, "STATS FR")
check("SWITCH is localizable", translatedItems[2].label, "ÉCHANGER")
check("MOVE is localizable", translatedItems[3].label, "DÉPLACER")
check("ITEM is localizable", translatedItems[4].label, "OBJET")
check("CANCEL is localizable", translatedItems[5].label, "ANNULER")
check("FNT is localizable", PartyMenu.rowFor(fnt).status, "K.O.")
check("EGG is localizable", PartyMenu.rowFor(egg()).name, "ŒUF")
party.tmhm = { move = "SURF" }
DATA.pokemon.CYNDAQUIL.tmhm = { "SURF" }
check("ABLE is localizable", party:tmhmAble(save.party[1]), "APTE")
check("NOT ABLE is localizable", party:tmhmAble(save.party[2]), "INAPTE")
DATA.pokemon.CYNDAQUIL.tmhm = nil
Strings.load(nil)

-- GiveTakePartyMonItem's first test is `cp EGG`: the held-item menu refuses.
game = newGame(save)
party = PartyMenu.new(game, { party = save.party, submenu = true })
party:openHeldItemMenu(1, egg())
check("the held-item menu refuses an egg", #game.stack._items, 0)

-- ------------------------------------------------------- SwitchPartyMons

-- The full flow through the pad: A opens the submenu, SWITCH holds the slot,
-- the second A swaps both the mons and their sPartyMail structs.
save = newSave()
Mail.set(save, 2, Mail.entry("FLOWER_MAIL", "hello", "GOLD", 12345))
game = newGame(save)
party = PartyMenu.new(game, { party = save.party, submenu = true,
  save = save })
game.input:press("a")
party:update(0)
check("a opens the submenu", party.submenu ~= nil, true)
game.input:press("down")
party:update(0)
check("down reaches SWITCH", party.submenu.items[party.submenu.index].id,
  "SWITCH")
game.input:press("a")
party:update(0)
check("SWITCH closes the submenu", party.submenu, nil)
check("and holds the slot", party.switchFrom, 1)
-- InitPartyMenuNoCancel: the cursor is capped at the last mon.
check("the CANCEL row is gone while switching", party:count(), 2)
game.input:press("down")
party:update(0)
check("down picks the other end", party.index, 2)
game.input:press("a")
party:update(0)
check("a releases the hold", party.switchFrom, nil)
check("the lead is now TOTODILE", save.party[1].nickname, "TOTODILE")
check("and slot 2 is CYNDAQUIL", save.party[2].nickname, "CYNDAQUIL")
-- _SwitchPartyMons' .SwapMonAndMail: the letter rides with its mon.
check("the mail moved with its mon", Mail.get(save, 1) ~= nil, true)
check("and left its old slot", Mail.get(save, 2), nil)
check("the CANCEL row is back", party:count(), 3)

-- B backs out of the hold without moving anything (.DontSwitch).
save = newSave()
game = newGame(save)
party = PartyMenu.new(game, { party = save.party, submenu = true,
  save = save })
party:beginSwitch(1)
check("beginSwitch holds the slot", party.switchFrom, 1)
game.input:press("b")
party:update(0)
check("b releases the hold", party.switchFrom, nil)
check("and nothing moved", save.party[1].nickname, "CYNDAQUIL")

-- Picking the held slot again is the `.skip` arm: nothing moves.
party:beginSwitch(1)
party.index = 1
game.input:press("a")
party:update(0)
check("the same slot swaps nothing", save.party[1].nickname, "CYNDAQUIL")
check("and the hold is released", party.switchFrom, nil)

-- `cp 2 / jr c, .DontSwitch`: one mon is nothing to switch with.
local lone = { mon("CYNDAQUIL", 12) }
game = newGame({ party = lone })
party = PartyMenu.new(game, { party = lone, submenu = true })
party:beginSwitch(1)
check("a lone mon cannot enter switch mode", party.switchFrom, nil)

-- A list opened over a table that is NOT the save's party (a battle copy)
-- reorders itself without touching sPartyMail.
save = newSave()
Mail.set(save, 2, Mail.entry("FLOWER_MAIL", "hello", "GOLD", 12345))
local copy = { save.party[1], save.party[2] }
game = newGame(save)
party = PartyMenu.new(game, { party = copy, submenu = true, save = save })
party:beginSwitch(1)
party.index = 2
game.input:press("a")
party:update(0)
check("the copy reordered", copy[1].nickname, "TOTODILE")
check("but the save's own party did not", save.party[1].nickname, "CYNDAQUIL")
check("and the mail stayed put", Mail.get(save, 2) ~= nil, true)

-- engine/pokemon/switchpartymons.asm:13
do
  local Sound = require("src.core.Sound")
  local realPlay, realResolve, realBusy, realFrames =
    Sound.play, Sound.resolve, Sound.sfxBusy, Sound.waitFramesFor
  local rang = {}
  Sound.play = function(_, name) rang[#rang + 1] = name end
  Sound.resolve = function(_, name) return name end
  Sound.sfxBusy = function() return false end
  Sound.waitFramesFor = function() return 0 end

  local function switchGame(withCue)
    local s = newSave()
    local g = newGame(s)
    g.data = setmetatable({
      audio = withCue and { sfx = { Sfx_SwitchPokemon = {} } } or { sfx = {} },
    }, { __index = DATA })
    return g, s
  end

  local g, s = switchGame(true)
  local p = PartyMenu.new(g, { party = s.party, submenu = true, save = s })
  p:beginSwitch(1)
  p.index = 2
  g.input:press("a")
  p:update(0)
  check("the switch swapped the slots", s.party[1].nickname, "TOTODILE")
  check("and beeps once in that frame", #rang, 1)
  p:update(0)
  check("the second beep follows on the next tick", #rang, 2)
  check("both are the switch cue",
    rang[1] == "Sfx_SwitchPokemon" and rang[2] == "Sfx_SwitchPokemon", true)
  p:update(0)
  check("and there is no third", #rang, 2)

  -- engine/pokemon/switchpartymons.asm:10
  rang = {}
  p:beginSwitch(1)
  p.index = 1
  g.input:press("a")
  p:update(0)
  p:update(0)
  check("the same slot rings nothing", #rang, 0)

  rang = {}
  g, s = switchGame(false)
  p = PartyMenu.new(g, { party = s.party, submenu = true, save = s })
  p:beginSwitch(1)
  p.index = 2
  g.input:press("a")
  p:update(0)
  p:update(0)
  check("no cue in the cache rings nothing", #rang, 0)
  check("and nothing is pending", p.repeatSfx, nil)

  -- home/audio.asm:225 WaitSFX
  Sound.sfxBusy = function() return true end
  Sound.waitFramesFor = function() return 3 end
  rang = {}
  g, s = switchGame(true)
  p = PartyMenu.new(g, { party = s.party, submenu = true, save = s })
  p:beginSwitch(1)
  p.index = 2
  g.input:press("a")
  p:update(0)
  check("the place beeps", #rang, 1)
  local held = p.index
  g.input:press("down")
  p:update(0)
  check("the pending beep holds the list", p.index, held)
  check("with no second beep yet", #rang, 1)
  p:update(0)
  check("still waiting", #rang, 1)
  p:update(0)
  check("the budget releases the second beep", #rang, 2)

  Sound.play, Sound.resolve, Sound.sfxBusy, Sound.waitFramesFor =
    realPlay, realResolve, realBusy, realFrames
end

-- ------------------------------------------------------------- egg summary

local at = SummaryMenu.at

-- EggStatsScreen, coordinate for coordinate.
save = newSave()
save.party[3] = egg(20)
cries = 0
game = newGame(save)
local screen = SummaryMenu.new(game, { party = save.party, index = 3,
  save = save })
check("an egg opens without a cry", cries, 0)
local page = screen:placements()
check("EGG at hlcoord 8,1", at(page, 8, 1), "EGG")
check("<ID>№. at hlcoord 8,3", at(page, 8, 3), "<ID>№.")
check("????? for the ID", at(page, 11, 3), "?????")
check("OT/ at hlcoord 8,5", at(page, 8, 5), "OT/")
check("????? for the OT", at(page, 11, 5), "?????")
-- No upper half: nothing names the species or its dex slot.
check("no dex number", at(page, 10, 0), nil)
check("no nickname row", at(page, 8, 2), nil)

-- The flavour ladder is `cp $6 / cp $b / cp $29` on the remaining cycles.
local function flavorLine(cycles)
  local s = SummaryMenu.new(newGame(save), { mon = egg(cycles), save = save })
  return at(s:eggPlacements(), 1, 9)
end
check("under 6 cycles it is about to hatch", flavorLine(5),
  "It's making sounds")
check("6 cycles is only close", flavorLine(6), "It moves around")
check("10 cycles is still close", flavorLine(10), "It moves around")
check("11 cycles needs more time", flavorLine(11), "Wonder what's")
check("40 cycles needs more time", flavorLine(40), "Wonder what's")
check("41 cycles needs a lot more", flavorLine(41), "This EGG needs a")
-- The close string is four lines, two rows apart (`next` steps two).
local closePage = SummaryMenu.new(newGame(save),
  { mon = egg(8), save = save }):eggPlacements()
check("close line 2 on row 11", at(closePage, 1, 11), "inside sometimes.")
check("close line 4 on row 15", at(closePage, 1, 15), "to hatching.")

-- EggStats_JoypadLoop: A and B both exit, and left/right turn no pages.
local closed = false
game = newGame(save)
screen = SummaryMenu.new(game, { party = save.party, index = 3, save = save })
screen.onClose = function() closed = true end
game.input:press("right")
screen:update(0)
check("right turns no page on an egg", screen.page, SummaryMenu.PINK_PAGE)
check("and does not close", closed, false)
game.input:press("a")
screen:update(0)
check("a exits the egg screen", closed, true)

closed = false
game = newGame(save)
screen = SummaryMenu.new(game, { party = save.party, index = 3, save = save })
screen.onClose = function() closed = true end
game.input:press("b")
screen:update(0)
check("b exits the egg screen too", closed, true)

-- EggStats_UpAction: up walks to the mon above, whose real page comes back.
game = newGame(save)
screen = SummaryMenu.new(game, { party = save.party, index = 3, save = save })
cries = 0
game.input:press("up")
screen:update(0)
check("up walks off the egg", screen.index, 2)
check("onto the mon's own page", at(screen:placements(), 8, 2), "TOTODILE")
check("and plays that mon's cry", cries, 1)

-- ...and walking back DOWN onto the egg swaps the egg page in, silently.
game.input:press("down")
screen:update(0)
check("down lands on the egg again", screen.index, 3)
check("as the egg page", at(screen:placements(), 8, 1), "EGG")
check("with no cry", cries, 1)

-- MoveScreenLoop's .cycle loops step over EGG slots: with the party
-- CYNDAQUIL / EGG / TOTODILE, right from slot 1 lands on slot 3.
save = newSave()
save.party = { save.party[1], egg(20), save.party[2] }
game = newGame(save)
screen = SummaryMenu.new(game, { party = save.party, index = 1, save = save })
screen.page = SummaryMenu.GREEN_PAGE
game.input:press("select")
screen:update(0)
check("select opens the move detail", screen.moveDetail, true)
game.input:press("right")
screen:update(0)
check("right skips the egg slot", screen.index, 3)
check("and stays in the move detail", screen.moveDetail, true)
game.input:press("left")
screen:update(0)
check("left skips it coming back", screen.index, 1)

-- --------------------------------------------------- the START menu wiring

-- src/core/Game2.lua's POKéMON row must ask for the submenu: the field list
-- is the one flavour that opens PokemonActionSubmenu on A
-- (engine/pokemon/mon_menu.asm) rather than answering to a caller.  A
-- textual check is the honest one here -- constructing a Game2 needs love --
-- and tests/drivers/gold_party_submenu.lua drives the real thing.
local game2Source = (function()
  local f = io.open("src/core/Game2.lua", "r")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end)()
check("Game2's source is readable", game2Source ~= nil, true)
if game2Source then
  local branch = game2Source:match(
    'elseif id == "pokemon" then(.-)elseif')
  check("the START menu's party list opens the action submenu",
    branch ~= nil and branch:find("submenu = true", 1, true) ~= nil, true)
end

-- ------------------------------------------------------ wPartyMenuCursor
--
-- InitPartyMenuWithCancel seeds wMenuCursorY from wPartyMenuCursor and only
-- falls back to row 1 when it is zero or no longer inside the party
-- (engine/pokemon/party_menu.asm:546), and PartyMenuSelect writes the picked
-- row back before the B test (:600) -- so the list reopens where it was left,
-- and only the CANCEL row leaves the byte alone.
do
  local cursorSave = newSave()
  local cursorGame = newGame(cursorSave)
  local list = PartyMenu.new(cursorGame, { party = cursorSave.party })
  check("a fresh session opens on the first mon", list.index, 1)
  list.index = 2
  list:storeCursor()
  check("PartyMenuSelect records the row", cursorGame.partyMenuCursor, 2)

  local reopened = PartyMenu.new(cursorGame, { party = cursorSave.party })
  check("and the list reopens on it", reopened.index, 2)

  -- The CANCEL row is one past the party and jumps out before the store.
  reopened.index = #cursorSave.party + 1
  reopened:storeCursor()
  check("CANCEL leaves the byte where it was", cursorGame.partyMenuCursor, 2)

  -- A byte pointing past a party that shrank falls back to row 1.
  cursorGame.partyMenuCursor = 5
  local shrunk = PartyMenu.new(cursorGame, { party = { cursorSave.party[1] } })
  check("a row past the party clamps to the first", shrunk.index, 1)
end

-- ---------------------------------------------------- the held-item marker
--
-- .SpawnItemIcon (engine/gfx/mon_icons.asm): a non-zero MON_ITEM swaps the
-- icon's frameset for _WITH_MAIL or _WITH_ITEM, whose OAM sets replace the
-- BOTTOM-LEFT quadrant with HeldItemIcons tile $08 (mail.2bpp) or $09
-- (item.2bpp).  The sheet is INCBIN'd mail first, so row 0 is mail.
do
  -- A save of its own: the blocks above reshuffle `save.party` and drop an
  -- egg into slot 2.
  local held = newSave()
  check("an empty hand gets no marker",
    PartyMenu.heldMarkerRow(held.party[2]), nil)
  check("a berry marks the icon with the item tile",
    PartyMenu.heldMarkerRow(held.party[1]), 1)
  local mailer = mon("TOTODILE", 10, { fields = { item = "FLOWER_MAIL" } })
  check("ItemIsMail picks the mail tile instead",
    PartyMenu.heldMarkerRow(mailer), 0)
  -- `ld a, [hl] / and a / ret z`: a zero item byte is an empty hand.
  check("a zero item byte is an empty hand",
    PartyMenu.heldMarkerRow({ item = 0 }), nil)

  -- The draw itself: three of the icon's four 8x8 quadrants plus the marker in
  -- place of the fourth, and one plain 16x16 quad when there is nothing to
  -- show.  Images are preloaded into iconCache so nothing reaches love.image.
  local iconImage = { getDimensions = function() return 16, 32 end }
  local markerImage = { getDimensions = function() return 8, 16 end }
  local marked = PartyMenu.new(newGame(held), {
    party = held.party,
    icons = {
      species = DATA.gen2Icons.species,
      icons = DATA.gen2Icons.icons,
      heldItem = { image = "x/held.png", width = 8, height = 8 },
    },
  })
  marked.iconCache["x/fox.png"] = iconImage
  marked.iconCache["x/monster.png"] = iconImage
  marked.iconCache["x/held.png"] = markerImage

  local calls = {}
  local realDraw = love.graphics.draw
  love.graphics.draw = function(image, _, x, y)
    calls[#calls + 1] = { image = image, x = x, y = y }
  end

  marked:drawIcon(held.party[1], 0, 0)
  check("a held item draws three icon quadrants plus the marker", #calls, 4)
  check("the marker comes from the HeldItemIcons sheet",
    calls[4] and calls[4].image, markerImage)
  check("and lands in the bottom-left quadrant",
    calls[4] and calls[4].x == 0 and calls[4].y == 8, true)
  check("the bottom-left species tile is replaced, not covered",
    calls[3] and calls[3].x == 8 and calls[3].y == 8, true)

  calls = {}
  marked:drawIcon(held.party[2], 0, 0)
  check("an empty hand is still one 16x16 draw", #calls, 1)

  -- A cache imported before the extractor read HeldItemIcons has no `heldItem`
  -- row: the list must draw exactly what it drew before, not error.
  local plain = PartyMenu.new(newGame(held), { party = held.party })
  plain.iconCache["x/fox.png"] = iconImage
  calls = {}
  plain:drawIcon(held.party[1], 0, 0)
  check("no marker sheet in the cache falls back to the plain icon",
    #calls, 1)

  love.graphics.draw = realDraw
end

print(("gen2 party menu: %d checks, %d failures"):format(checks, failures))
-- Raise rather than os.exit: tests/run_tests.lua dofiles this file, so an
-- exit here takes the whole tier down with it and silently skips every
-- suite listed after this one (see tests/harness.lua's T.suite note).
if failures > 0 then
  error(("%d assertion(s) failed"):format(failures), 0)
end
