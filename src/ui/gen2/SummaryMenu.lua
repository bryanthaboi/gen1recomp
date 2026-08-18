-- Gold's mon SUMMARY, transcribed from engine/pokemon/stats_screen.asm.
--
-- Three pages, named after the palette each one wears rather than after what
-- it shows: PINK_PAGE (1), GREEN_PAGE (2), BLUE_PAGE (3).  It is worth saying
-- out loud which is which, because Gen 1's stats screen split the same
-- information differently and the temptation is to lay this out from memory:
--
--   PINK   HP bar, HP digits, STATUS/TYPE, and the EXP POINTS / LEVEL UP TO
--          block down the right of a vertical rule at column 9
--   GREEN  the held ITEM, then the four moves with their PP
--   BLUE   OT / <ID>№ down the left of a vertical rule at column 10, and the
--          five non-HP stats down its right
--
-- None of the three is a text box.  StatsScreenMain calls ClearTilemap and
-- then every routine writes tiles at its own hlcoord, so every coordinate in
-- this file is that hlcoord and nothing here is placed by eye.
--
-- StatsScreen_InitUpperHalf draws rows 0-7 once and no page redraws them, so
-- the pic, dex number, nickname, level, gender, species and the row-7 rule
-- stay put while the lower half changes.  That is why `upperPlacements` is
-- separate from the per-page ones and why switching pages does not replay the
-- cry: LoadPinkPage only jumps to StatsScreen_PlaceFrontpic (which calls
-- PlayMonCry) when b is 0, and b is 0 only on the entry from StatsScreenMain
-- -- a page switch comes back through .done_loading with `ld b, 1`.
--
-- Tiles that are not glyphs
-- -------------------------
-- StatsScreen_LoadFont (engine/gfx/load_font.asm) is _LoadFontsBattleExtra
-- plus ExpBarGFX at $55, and LoadStatsScreenPageTilesGFX puts the 17 tiles of
-- gfx/stats/stats_tiles.png at $31:
--
--   $31        the vertical divider column
--   $36-$39    the small (inactive) page square, 2x2
--   $3a-$3d    the large (active) page square, 2x2
--   $3e        the "P" of the PP label
--   $3f        the shiny ⁂ icon (stats_tiles tile 14)
--   $40 / $41  the left and right HP/exp bar end caps
--
-- The extractor does not carry that sheet yet, so `pageTile` draws those seven
-- shapes directly and takes the sheet the moment menu_gfx grows a `stats`
-- entry.  Everything that IS a glyph goes through the font: ◀ ($71), ▶ ($ed),
-- № ($74), <ID> ($73), <LV> ($6e) and the row-7 rule's $62 (the empty HP/exp
-- bar cell, which is FontBattleExtra's -- hence Font.useBattleExtra(true)
-- around the whole screen, exactly as the party menu does).
--
-- Move descriptions
-- -----------------
-- The three stats pages have no room for one: LoadGreenPage's ClearBox is
-- rows 8-17 and the move names and PP already fill every one of them.  Where
-- the cart shows a move description is PlaceMoveData (engine/pokemon/
-- mon_menu.asm), the screen MoveScreenLoop puts up, and that whole screen is
-- transcribed here as `moveDetailPlacements`.  SELECT opens it from the green
-- page; SELECT is not in the stats screen's accepted-button mask
-- (PAD_CTRL_PAD | PAD_A | PAD_B), so borrowing it leaves every button the ASM
-- does handle behaving exactly as it does.
--
-- ManagePokemonMoves (engine/pokemon/mon_menu.asm:858) opens that same screen
-- on its own, which is what the party submenu's MOVE row does: `moveScreen`
-- says the move list IS the screen, so B exits instead of dropping onto a page.

local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local Font = require("src.render.Font")
local GbcPalette = require("src.render.GbcPalette")
local HpBar = require("src.battle.gen2.HpBar")
local ItemEffects = require("src.core.gen2.ItemEffects")
local Mon = require("src.battle.gen2.Mon")
local Palettes = require("src.world.gen2.Palettes")
local Pokerus = require("src.core.gen2.Pokerus")
local Unown = require("src.core.gen2.Unown")

local SummaryMenu = {}
SummaryMenu.__index = SummaryMenu
SummaryMenu.isOpaque = true

-- The *_PAGE constants at the top of stats_screen.asm.
SummaryMenu.PINK_PAGE = 1
SummaryMenu.GREEN_PAGE = 2
SummaryMenu.BLUE_PAGE = 3
SummaryMenu.NUM_STAT_PAGES = 3

local PINK_PAGE = SummaryMenu.PINK_PAGE
local GREEN_PAGE = SummaryMenu.GREEN_PAGE
local BLUE_PAGE = SummaryMenu.BLUE_PAGE

-- Tile ids from StatsScreenPageTilesGFX, kept named so `pageTile` reads like
-- the ASM that asks for them.
local TILE_VERTICAL_DIVIDER = 0x31
local TILE_SQUARE_SMALL = 0x36
local TILE_SQUARE_LARGE = 0x3a
local TILE_SHINY = 0x3f
local TILE_BAR_CAP_LEFT = 0x40
local TILE_BAR_CAP_RIGHT = 0x41
-- FontBattleExtra's empty HP/exp bar cell, which is what the row-7 rule is
-- made of (StatsScreen_PlaceHorizontalDivider).
local TILE_HORIZONTAL_DIVIDER = 0x62

-- PrintTempMonStats' .StatNames, and the wTempMon fields it prints beside
-- them.  <NEXT> steps two rows, so the five labels are 2 rows apart and the
-- values start one row below the first label.
local STAT_LABELS = { "ATTACK", "DEFENSE", "SPCL.ATK", "SPCL.DEF", "SPEED" }
local STAT_KEYS = {
  "attack", "defense", "specialAttack", "specialDefense", "speed",
}

-- data/types/names.asm.  Every type constant prints as its own name except
-- the two the extractor has to disambiguate against Lua-unfriendly ids.
local TYPE_NAMES = {
  PSYCHIC_TYPE = "PSYCHIC",
  CURSE_TYPE = "???",
}

-- Gen 2 pics are 5x5, 6x6 or 7x7 and PadFrontpic centres the small ones in
-- the 7x7 block PrepMonFrontpic lays at hlcoord 0, 0.  Same table the dex
-- uses, for the same reason.
local PIC_PAD = { [7] = { 0, 0 }, [6] = { 1, 1 }, [5] = { 1, 2 } }

-- Matches src/core/gen2/Breeding.lua's isEgg without requiring it, the same
-- arms-length test src/core/gen2/Happiness.lua carries.
local function isEggMon(mon)
  return type(mon) == "table" and mon.isEgg == true
end

-- EggStatsScreen's four flavour strings, picked off wTempMonHappiness --
-- which on an egg is not happiness at all but the remaining hatch cycles
-- DoEggStep counts down (256 steps each, `eggSteps` here).  The thresholds
-- are the ASM's own `cp $6 / cp $b / cp $29` ladder, and the lines join with
-- <NEXT> exactly as the db/next strings do.
local EGG_FLAVOR = {
  { below = 0x6, text = "It's making sounds<NEXT>inside. It's going"
      .. "<NEXT>to hatch soon!" },
  { below = 0xb, text = "It moves around<NEXT>inside sometimes."
      .. "<NEXT>It must be close<NEXT>to hatching." },
  { below = 0x29, text = "Wonder what's<NEXT>inside? It needs"
      .. "<NEXT>more time, though." },
  { text = "This EGG needs a<NEXT>lot more time to<NEXT>hatch." },
}

local function eggFlavor(cycles)
  for _, entry in ipairs(EGG_FLAVOR) do
    if not entry.below or cycles < entry.below then return entry.text end
  end
end

-- ------------------------------------------------------------- placements
--
-- Every page is built as a list of { text, x, y } tilemap writes before
-- anything is drawn, so the layout can be asserted without a graphics device
-- (tests/gen2_summary_test.lua) and `drawPanel` stays a loop.

local function put(list, text, x, y)
  if text == nil then return list end
  list[#list + 1] = { text = tostring(text), x = x, y = y }
  return list
end

-- The text a placement list writes at a coordinate, or nil.
function SummaryMenu.at(placements, x, y)
  for _, entry in ipairs(placements or {}) do
    if entry.x == x and entry.y == y then return entry.text end
  end
  return nil
end

-- PrintNum: a right-aligned field, space-padded unless PRINTNUM_LEADINGZEROS.
local function num(value, width, leadingZeros)
  return Chrome.number(value, width, leadingZeros)
end

-- How many tiles a string occupies, which is what PlaceString advances by --
-- not its pixel width.  "<PK>" and "é" are one tile each, and Font.split is
-- the only thing in the port that knows that.
local function tiles(text)
  return #Font.split(tostring(text or ""))
end

-- GetNickname reads wPartyMonNicknames, so a party mon always has a name of
-- its own; a directly-built mon may only carry a species.
local function monName(mon)
  return mon.nickname or mon.name or mon.species or "?"
end

-- Blank whole tile cells.  PlaceString writes tilemap cells, so a string put
-- over a box border REPLACES it; here the border is pixels and a glyph sheet
-- is transparent, so without this the frame runs straight through the letters
-- of any string the ASM places on a border row.
local function clearCells(tx, ty, tw, th)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", tx * 8, ty * 8, tw * 8, (th or 1) * 8)
  G.setColor(0, 0, 0, 1)
end

-- PrintLevel (home/pokemon.asm): '<LV>' then the number left-aligned in two
-- cells.  A three-digit level does `dec hl` first, so the digits overwrite the
-- <LV> and the field starts at the same column either way.
local function levelText(level)
  level = math.max(1, math.floor(tonumber(level) or 1))
  if level >= 100 then return tostring(level) end
  return "<LV>" .. tostring(level)
end

-- PlaceStatusString (engine/pokemon/mon_stats.asm): three letters, and a mon
-- with no HP reads FNT whatever its status byte says.  Same lookup the party
-- list makes; both screens call the same routine on the cart.
local function statusText(mon)
  if (mon.hp or 0) <= 0 then return "FNT" end
  local status = mon.status
  if not status then return nil end
  local class = ItemEffects.STATUS_CLASS[tostring(status):lower()]
  return class and class:upper()
end

-- wTempMonPokerusStatus is one byte: the low nibble counts the days left and
-- the high nibble holds the strain.  A cured mon keeps a non-zero high nibble
-- forever, and that is what the '.' at (8,8) marks -- so "infected" and
-- "immune" really are two different tests of the same byte, in that order.
local function pokerusState(mon)
  if Pokerus.isInfected(mon) then return "infected" end
  if Pokerus.isImmune(mon) then return "immune" end
  return nil
end

-- ------------------------------------------------------------------ screen

function SummaryMenu:wantsFillScale() return true end
function SummaryMenu:drawsWidescreen() return true end

-- opts: mon, party, index, page, moveScreen, onClose(), save, pokemon, moves,
--       items, palettes, menuGfx
function SummaryMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, SummaryMenu)
  self.game = game
  local data = (game and game.data) or {}
  self.save = opts.save or (game and game.save)
  self.pokemon = opts.pokemon or data.pokemon
  self.moves = opts.moves or data.moves
  self.items = opts.items or data.items
  self.palettes = opts.palettes or data.gen2Palettes
  -- The egg page's pic does not live in data.pokemon; it comes off the same
  -- menu_gfx.eggHatch entry the hatch cutscene draws.
  self.menuGfx = opts.menuGfx or data.gen2MenuGfx
  -- ...and icons.lua carries ICON_EGG, which is what stands in when a cache
  -- was built before the extractor learned EggPic.  See drawEggPic.
  self.icons = opts.icons or data.gen2Icons
  self.onClose = opts.onClose
  if opts.mon and not opts.party then
    -- One mon on its own: the wMonType == TEMPMON / BOXMON path, where the
    -- `down` and `.d_up` arms have nothing to scroll to.
    self.party = { opts.mon }
    self.index = 1
    self.mon = opts.mon
  else
    self.party = opts.party or (self.save and self.save.party) or {}
    self.index = math.max(1,
      math.min(opts.index or 1, math.max(1, #self.party)))
    self.mon = self.party[self.index]
  end
  -- engine/pokemon/move_mon.asm:1402
  Mon.refreshStats(self.mon, data)
  self.page = opts.page or PINK_PAGE
  -- ManagePokemonMoves opens straight onto MoveScreenLoop's screen; SELECT off
  -- the green page reaches the same view with the stats pages still behind it.
  self.moveScreen = opts.moveScreen == true
  self.moveDetail = self.moveScreen
  self.moveIndex = 1
  -- wSwappingMove: the row A picked a move up from, nil while nothing is held.
  self.swapFrom = nil
  self.picCache = {}

  -- The HP and exp bars are the battle HUD's, tile for tile: DrawPlayerHP is
  -- DrawBattleHPBar and the exp bar is FillInExpBar, so both go through
  -- BattleHud rather than being drawn a second time here.
  local BattleHud = require("src.ui.gen2.BattleHud")
  self.hud = BattleHud.new(data.gen2MenuGfx, self.palettes)
  self:playCry()
  return self
end

-- StatsScreen_PlaceFrontpic ends in PlayMonCry, and it only runs when b is 0
-- -- the entry from StatsScreenMain.  So the cry fires on open and on a mon
-- switch, never on a page switch.
function SummaryMenu:playCry()
  local mon = self.mon
  -- SetUpMoveScreenBG only loads the menu icon (engine/pokemon/mon_menu.asm:
  -- 1106-1107); MoveScreenLoop has no PlayMonCry at all, on entry or on cycle.
  if self.moveScreen then return end
  -- StatsScreenInit routes an EGG to EggStatsInit before any pic or cry, so
  -- an egg never plays the hidden species' voice.  EggStatsScreen ends on its
  -- own cue instead (engine/pokemon/stats_screen.asm:788): `ld a,
  -- [wTempMonHappiness] / cp 6 / ret nc / ld de, SFX_2_BOOPS`, i.e. the boops
  -- sound only once the egg is nearly ready, pairing with the "It's making
  -- sounds inside" line.  The threshold is the same $6 EGG_FLAVOR's first row
  -- reads off eggSteps, so the two cannot drift apart.
  if isEggMon(mon) then
    if (mon.eggSteps or 0) >= 0x6 then return end
    if not (self.game and self.game.data) then return end
    local ok, Sound = pcall(require, "src.core.Sound")
    if ok and Sound and Sound.play then
      pcall(Sound.play, self.game.data, "Sfx_2Boops")
    end
    return
  end
  if not (mon and mon.species and self.game and self.game.data) then return end
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound and Sound.playCry then
    pcall(Sound.playCry, self.game.data, mon.species)
  end
end

function SummaryMenu:speciesDef()
  local mon = self.mon
  return mon and self.pokemon and self.pokemon[mon.species] or nil
end

function SummaryMenu:moveDef(id)
  return id and self.moves and self.moves[id] or nil
end

-- The mon's four move slots, empty ones left as holes so the '-' rows land on
-- the right lines.
function SummaryMenu:moveList()
  return (self.mon and self.mon.moves) or {}
end

function SummaryMenu:moveName(entry)
  if not entry then return nil end
  local def = self:moveDef(entry.id)
  return (def and def.name) or entry.id
end

-- The EXP page's "to next level" gap reads the same curve the battle does, so
-- it goes through Mon.growthFor.  self.pokemon IS data.pokemon, so a synthetic
-- data table with just that key is what the accessor needs.
function SummaryMenu:growth()
  local def = self:speciesDef()
  if not (self.pokemon and def) then return nil end
  local data = (self.game and self.game.data) or { pokemon = self.pokemon }
  return require("src.battle.gen2.Mon").growthFor(data, def.growthRate)
end

-- .CalcExpToNextLevel: zero at MAX_LEVEL, otherwise the gap to the next
-- level's threshold.
function SummaryMenu:expToNext()
  local mon = self.mon or {}
  local level = mon.level or 1
  if level >= Mon.MAX_LEVEL then return 0 end
  return math.max(0, Mon.experienceForLevel(self:growth(), level + 1)
    - (mon.experience or 0))
end

function SummaryMenu:otName()
  local mon = self.mon or {}
  if mon.otName then return mon.otName end
  local player = (self.save and self.save.player) or {}
  return player.name or "GOLD"
end

function SummaryMenu:otId()
  local mon = self.mon or {}
  if mon.otId then return mon.otId end
  local player = (self.save and self.save.player) or {}
  return player.id or 0
end

-- .PlaceOTInfo's closing block: `lb bc, 0, -1` counts the characters up to the
-- '@', then `ld a, NAME_LENGTH - 1; sub c` and, unless that came out under
-- NAME_LENGTH - PLAYER_NAME_LENGTH (3), clamps to
-- NAME_LENGTH - PLAYER_NAME_LENGTH - 1 (2).  So an ordinary name gets two
-- spaces of left padding and only a 9 or 10 character one is pulled left.
function SummaryMenu.otColumn(name)
  local pad = 10 - tiles(name)
  if pad >= 3 or pad < 0 then pad = 2 end
  return pad
end

function SummaryMenu:itemName()
  local mon = self.mon or {}
  if not mon.item then return nil end
  local def = self.items and self.items[mon.item]
  return (def and def.name) or mon.item
end

function SummaryMenu:typeNames()
  local def = self:speciesDef()
  local types = (self.mon and self.mon.types) or (def and def.types) or {}
  local first = types[1]
  local second = types[2] or first
  local function name(id)
    if not id then return nil end
    return TYPE_NAMES[id] or id
  end
  -- PrintMonTypes' .hide_type_2: a single-typed mon really has two of the same
  -- type, and the second name is blanked rather than printed twice.
  if first and second and first == second then return name(first), nil end
  return name(first), name(second)
end

-- ------------------------------------------------------------ upper half

-- StatsScreen_InitUpperHalf, coordinate for coordinate.
function SummaryMenu:upperPlacements()
  local mon = self.mon or {}
  local def = self:speciesDef()
  local out = {}
  -- (8,0) '№' and (9,0) '.' are two `ld [hl]` writes, then PrintNum puts the
  -- dex number in three leading-zero digits at (10,0).
  put(out, "№.", 8, 0)
  put(out, num(def and def.dex or 0, 3, true), 10, 0)
  put(out, levelText(mon.level), 14, 0)
  put(out, mon.nickname or mon.name or mon.species, 8, 2)
  -- GetGender returns carry for a genderless species, and nothing is written.
  if mon.gender == "male" then
    put(out, "♂", 18, 0)
  elseif mon.gender == "female" then
    put(out, "♀", 18, 0)
  end
  -- (9,4) is a bare '/' written with `ld [hli], a`, so the species name that
  -- follows starts at (10,4).
  put(out, "/", 9, 4)
  put(out, (def and def.name) or mon.species, 10, 4)
  return out
end

-- ------------------------------------------------------------- pink page

function SummaryMenu:pinkPlacements()
  local mon = self.mon or {}
  local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 0
  local out = {}

  -- DrawPlayerHP puts the bar at (0,9) and then, from that same hl,
  -- `bccoord 1, 1, 0` steps to (1,10) for the digits: current HP in three
  -- columns, the '/' it writes with `ld [hli]`, then max HP in three more.
  put(out, num(mon.hp, 3), 1, 10)
  put(out, "/", 4, 10)
  put(out, num(maxHp, 3), 5, 10)

  -- .Status_Type is "STATUS/" <NEXT> "TYPE/", and <NEXT> is two rows down at
  -- the same column -- so the second label is at row 14, not row 13.
  put(out, "STATUS/", 0, 12)
  put(out, "TYPE/", 0, 14)

  local pokerus = pokerusState(mon)
  if pokerus == "infected" then
    -- .PkrsStr is "#RUS", and '#' is the four-tile POKé compression byte.
    put(out, "POKéRUS", 1, 13)
  else
    if pokerus == "immune" then put(out, ".", 8, 8) end
    put(out, statusText(mon) or "OK", 6, 13)
  end

  -- PrintMonTypes writes type 1 at (1,15) and type 2 two rows below it, and
  -- then LoadPinkPage copies the nine bytes of row 17 up onto row 16 and
  -- blanks row 17 -- so the second type ends up one row under the first.
  local type1, type2 = self:typeNames()
  put(out, type1, 1, 15)
  put(out, type2, 1, 16)

  put(out, "EXP POINTS", 10, 9)
  -- `lb bc, 3, 7`: a three-byte value in seven columns, so the field runs
  -- (13,10) to (19,10).
  put(out, num(mon.experience, 7), 13, 10)
  put(out, "LEVEL UP", 10, 12)
  put(out, num(self:expToNext(), 7), 13, 13)
  put(out, "TO", 14, 14)
  -- The level printed at (17,14) is the NEXT one: LoadPinkPage bumps
  -- wTempMonLevel, calls PrintLevel, and puts it back.  MAX_LEVEL stays put.
  local level = mon.level or 1
  put(out, levelText(math.min(Mon.MAX_LEVEL, level + 1)), 17, 14)
  return out
end

-- ------------------------------------------------------------ green page

function SummaryMenu:greenPlacements()
  local out = {}
  put(out, "ITEM", 0, 8)
  put(out, self:itemName() or "---", 6, 8)
  put(out, "MOVE", 0, 10)

  -- ListMoves runs from (8,10) with wListMovesLineSpacing = SCREEN_WIDTH * 2,
  -- so the four names are two rows apart; ListMovePP runs from (12,11) with
  -- the same spacing, one row below each name.  An empty slot gets a single
  -- '-' for the name and the PP label's two cells get '-' as well.
  local moves = self:moveList()
  for slot = 1, 4 do
    local nameY = 10 + (slot - 1) * 2
    local ppY = nameY + 1
    local entry = moves[slot]
    if entry then
      put(out, self:moveName(entry), 8, nameY)
      -- Two $3e "P" tiles: `ld [hli], a` then `ld [hld], a` writes the same
      -- tile at (12,y) and (13,y).
      put(out, "PP", 12, ppY)
      -- `pop hl` then three `inc hl` lands the numbers at (15,y): two digits,
      -- the '/' PrintNum's caller writes, then two more.
      put(out, num(entry.pp, 2), 15, ppY)
      put(out, "/", 17, ppY)
      put(out, num(entry.maxPp or entry.pp, 2), 18, ppY)
    else
      put(out, "-", 8, nameY)
      put(out, "--", 12, ppY)
    end
  end
  return out
end

-- ------------------------------------------------------------- blue page

function SummaryMenu:bluePlacements()
  local mon = self.mon or {}
  local out = {}
  -- IDNoString is "<ID>№." -- three single tiles, not the seven letters of
  -- "ID No." -- and OTString is "OT/".
  put(out, "<ID>№.", 0, 9)
  put(out, num(self:otId(), 5, true), 2, 10)
  put(out, "OT/", 0, 12)
  local ot = self:otName()
  put(out, ot, SummaryMenu.otColumn(ot), 13)

  -- PrintTempMonStats is called at (11,8) with bc = 6: the labels go in at hl
  -- two rows apart, then `add hl, bc` and one more SCREEN_WIDTH puts the first
  -- value at (17,9) -- three columns wide, so every value ends at column 19.
  for i, label in ipairs(STAT_LABELS) do
    put(out, label, 11, 8 + (i - 1) * 2)
    local value = (mon.stats or {})[STAT_KEYS[i]]
    put(out, num(value, 3), 17, 9 + (i - 1) * 2)
  end
  return out
end

-- ------------------------------------------------------- move detail view
--
-- SetUpMoveScreenBG + SetUpMoveList + PlaceMoveData (engine/pokemon/
-- mon_menu.asm).  Two text boxes: Textbox (0,1) with a 9x18 interior, so rows
-- 1-11, and Textbox (0,11) with a 5x18 interior, so rows 11-17 -- the two
-- share row 11, which is why the TYPE plaque's bottom line sits on it.

function SummaryMenu:moveDetailPlacements()
  local mon = self.mon or {}
  local out = {}
  local name = monName(mon)
  put(out, name, 5, 1)
  -- PlaceString leaves bc one tile past the string and MoveScreenLoop pops
  -- that straight into hl for PrintLevel, so the level butts up against the
  -- nickname rather than sitting in a column.
  put(out, levelText(mon.level), 5 + tiles(name), 1)

  local moves = self:moveList()
  for slot = 1, 4 do
    local nameY = 3 + (slot - 1) * 2
    local ppY = nameY + 1
    local entry = moves[slot]
    if entry then
      put(out, self:moveName(entry), 2, nameY)
      put(out, "PP", 10, ppY)
      put(out, num(entry.pp, 2), 13, ppY)
      put(out, "/", 15, ppY)
      put(out, num(entry.maxPp or entry.pp, 2), 16, ppY)
    else
      put(out, "-", 2, nameY)
      put(out, "--", 10, ppY)
    end
  end

  -- .moving_move: five spaces over "TYPE/" at (1,11), ClearBox (1,12) 5x18,
  -- then String_MoveWhere at (1,12) -- so the data half reads "Where?" alone.
  if self.swapFrom then
    put(out, "┌─────┐", 0, 10)
    put(out, "│", 0, 11)
    put(out, "└", 6, 11)
    put(out, "Where?", 1, 12)
    return out
  end

  -- String_MoveType_Top / _Bottom are box-drawing glyphs, and the plaque is
  -- open on its right: "┌─────┐" over "│TYPE/└".
  put(out, "┌─────┐", 0, 10)
  put(out, "│TYPE/└", 0, 11)
  put(out, "ATTK/", 11, 12)

  local entry = moves[self.moveIndex]
  local def = entry and self:moveDef(entry.id)
  local moveType = def and def.type
  put(out, moveType and (TYPE_NAMES[moveType] or moveType) or "---", 2, 12)
  -- `cp 2; jr c, .no_power`: a move with power 0 or 1 prints String_MoveNoPower
  -- rather than a number.
  local power = (def and def.power) or 0
  if power >= 2 then
    put(out, num(power, 3), 16, 12)
  else
    put(out, "---", 16, 12)
  end

  -- PrintMoveDescription at (1,14).  Descriptions join their lines with
  -- <NEXT>, which is two rows down at the same column, so the second line is
  -- at row 16 and not row 15.
  local description = def and def.description or ""
  local ty = 14
  for line in (tostring(description) .. "<NEXT>"):gmatch("(.-)<NEXT>") do
    if ty > 16 then break end
    if line ~= "" then put(out, line, 1, ty) end
    ty = ty + 2
  end
  return out
end

-- --------------------------------------------------------------- egg page
--
-- EggStatsScreen (engine/pokemon/stats_screen.asm).  One screen, no pages,
-- no arrows, no gender glyph: "EGG" where the nickname block sits, five
-- question marks for both the ID and the OT, and a flavour line that reads
-- the hatch counter.  Everything else about the egg -- species, level,
-- stats, moves -- stays a secret.

function SummaryMenu:eggPlacements()
  local mon = self.mon or {}
  local out = {}
  put(out, "EGG", 8, 1)
  -- IDNoString / OTString, the same strings the blue page prints, with
  -- FiveQMarkString beside each: an egg's OT and ID are hidden.
  put(out, "<ID>№.", 8, 3)
  put(out, "?????", 11, 3)
  put(out, "OT/", 8, 5)
  put(out, "?????", 11, 5)
  local ty = 9
  for line in ((eggFlavor(mon.eggSteps or 0) or "") .. "<NEXT>")
      :gmatch("(.-)<NEXT>") do
    if line ~= "" then put(out, line, 1, ty) end
    ty = ty + 2
  end
  return out
end

-- Everything the current view writes, upper half included.  The move detail
-- clears the tilemap for itself (SetUpMoveScreenBG), so it does not carry it.
function SummaryMenu:placements()
  if isEggMon(self.mon) then return self:eggPlacements() end
  if self.moveDetail then return self:moveDetailPlacements() end
  local out = self:upperPlacements()
  local page
  if self.page == GREEN_PAGE then
    page = self:greenPlacements()
  elseif self.page == BLUE_PAGE then
    page = self:bluePlacements()
  else
    page = self:pinkPlacements()
  end
  for _, entry in ipairs(page) do out[#out + 1] = entry end
  return out
end

-- ------------------------------------------------------------------- input

function SummaryMenu:close()
  if self.onClose then self.onClose() end
end

-- .d_right / .d_left.  Right adds one and wraps past BLUE_PAGE back to
-- PINK_PAGE; left subtracts one and wraps from zero to BLUE_PAGE.
function SummaryMenu:turnPage(delta)
  local page = self.page + delta
  if page > BLUE_PAGE then page = PINK_PAGE end
  if page < PINK_PAGE then page = BLUE_PAGE end
  self.page = page
end

-- The `down` and `.d_up` arms: no wrap at either end (both `jr z, .joypad_loop`
-- out rather than rolling round), and the page survives the switch because
-- StatsScreenMain pushes bc on the way in and pops it before jumping to the
-- page loader.
function SummaryMenu:switchMon(delta)
  local next_ = self.index + delta
  if next_ < 1 or next_ > #self.party then return false end
  self.index = next_
  self.mon = self.party[next_]
  -- engine/pokemon/move_mon.asm:1402
  Mon.refreshStats(self.mon, self.game and self.game.data)
  self.moveIndex = 1
  self:playCry()
  return true
end

-- MoveScreenLoop's .cycle_right_loop / .cycle_left_loop: the move screen
-- walks the party but steps over EGG slots (`cp EGG / ret nz` inverted), so
-- it never opens on one.  No wrap at either end, like switchMon.
function SummaryMenu:switchMonPastEggs(delta)
  local next_ = self.index + delta
  while self.party[next_] and isEggMon(self.party[next_]) do
    next_ = next_ + delta
  end
  if next_ < 1 or next_ > #self.party then return false end
  self.index = next_
  self.mon = self.party[next_]
  -- engine/pokemon/move_mon.asm:1402
  Mon.refreshStats(self.mon, self.game and self.game.data)
  self.moveIndex = 1
  self:playCry()
  return true
end

-- .place_move's `.copy_move` pair swaps the move byte and then the PP byte, so
-- a slot travels whole -- id, PP and the PP-Up ceiling ride in one entry here.
function SummaryMenu:swapMoves(from, to)
  local moves = self.mon and self.mon.moves
  if not (moves and from and to) or from == to then return false end
  if not (moves[from] and moves[to]) then return false end
  moves[from], moves[to] = moves[to], moves[from]
  return true
end

-- .swap_moves plays SFX_SWITCH_POKEMON twice (mon_menu.asm:1036-1041); a cache
-- without that cue simply makes no sound, the way the box menu guards its own.
function SummaryMenu:playSwapSfx()
  local data = self.game and self.game.data
  local ok, Sound = pcall(require, "src.core.Sound")
  if not (ok and data and Sound and Sound.play) then return end
  local sfx = data.audio and data.audio.sfx
  if sfx and sfx[Sound.resolve(data, "Sfx_SwitchPokemon")] then
    pcall(Sound.play, data, "Sfx_SwitchPokemon")
  end
end

-- MoveScreenLoop's .joy_loop.  A picks a move up (.a_button stores wMenuCursorY
-- in wSwappingMove and draws the hollow cursor) and puts it down (.place_move);
-- B drops it back on the row it came from and only then exits.
function SummaryMenu:updateMoveDetail(input)
  local moves = self:moveList()
  local count = math.max(1, #moves)
  if input:wasPressed("up") then
    self.moveIndex = self.moveIndex > 1 and self.moveIndex - 1 or count
  elseif input:wasPressed("down") then
    self.moveIndex = self.moveIndex < count and self.moveIndex + 1 or 1
  elseif input:wasPressed("a") then
    if self.swapFrom then
      if self:swapMoves(self.swapFrom, self.moveIndex) then self:playSwapSfx() end
      self.swapFrom = nil
    elseif moves[self.moveIndex] then
      self.swapFrom = self.moveIndex
    end
  elseif input:wasPressed("right") then
    -- MoveScreenLoop's .d_right / .d_left walk the party rather than the page,
    -- and both `jp nz, .joy_loop` straight back out while a move is held.
    if not self.swapFrom then self:switchMonPastEggs(1) end
  elseif input:wasPressed("left") then
    if not self.swapFrom then self:switchMonPastEggs(-1) end
  elseif input:wasPressed("b") or input:wasPressed("select") then
    if self.swapFrom then
      self.moveIndex = self.swapFrom
      self.swapFrom = nil
    elseif self.moveScreen then
      -- .exit: ManagePokemonMoves' whole screen goes, back to the party list.
      self:close()
    else
      self.moveDetail = false
    end
  end
end

function SummaryMenu:update(_dt)
  local input = self.game and self.game.input
  if not input then return end
  if self.moveDetail then
    self:updateMoveDetail(input)
    return
  end

  -- EggStats_JoypadLoop masks PAD_DOWN | PAD_UP | PAD_A | PAD_B: A and B
  -- both exit (StatsScreen_Exit), up and down walk the party, and there are
  -- no pages to turn.
  if isEggMon(self.mon) then
    if input:wasPressed("a") or input:wasPressed("b") then
      self:close()
    elseif input:wasPressed("up") then
      self:switchMon(-1)
    elseif input:wasPressed("down") then
      self:switchMon(1)
    end
    return
  end

  -- .joypad_action masks with PAD_CTRL_PAD | PAD_A | PAD_B and tests B first.
  if input:wasPressed("b") then
    self:close()
    return
  end
  if input:wasPressed("left") then
    self:turnPage(-1)
    return
  end
  if input:wasPressed("right") then
    self:turnPage(1)
    return
  end
  if input:wasPressed("a") then
    -- .a_button quits on the last page and otherwise FALLS THROUGH into
    -- .d_right; the fallthrough is the whole behaviour, not a missing branch.
    if self.page == BLUE_PAGE then
      self:close()
    else
      self:turnPage(1)
    end
    return
  end
  if input:wasPressed("up") then
    self:switchMon(-1)
    return
  end
  if input:wasPressed("down") then
    self:switchMon(1)
    return
  end
  -- The port's own hook onto MoveScreenLoop; see the header.
  if input:wasPressed("select") and self.page == GREEN_PAGE then
    self.moveDetail = true
    self.moveIndex = 1
  end
end

-- ----------------------------------------------------------------- drawing

-- A tile out of StatsScreenPageTilesGFX.  The extractor does not carry that
-- sheet, so each of the seven shapes it needs is drawn here; the moment
-- menu_gfx grows a `stats` entry this can take the real tiles instead.
function SummaryMenu:pageTile(id, tx, ty)
  local G = love.graphics
  local px, py = tx * 8, ty * 8
  G.setColor(0, 0, 0, 1)
  if id == TILE_VERTICAL_DIVIDER then
    G.rectangle("fill", px + 3, py, 2, 8)
  elseif id == TILE_BAR_CAP_LEFT then
    G.rectangle("fill", px + 6, py + 1, 2, 6)
  elseif id == TILE_BAR_CAP_RIGHT then
    G.rectangle("fill", px, py + 1, 2, 6)
  elseif id == TILE_SHINY then
    -- ⁂ is an asterism: three dots, two low and one high.
    G.rectangle("fill", px + 2, py + 1, 2, 2)
    G.rectangle("fill", px, py + 4, 2, 2)
    G.rectangle("fill", px + 4, py + 4, 2, 2)
  end
  G.setColor(1, 1, 1, 1)
end

-- StatsScreen_LoadPageIndicators: three 2x2 squares at (13,5), (15,5) and
-- (17,5), all small ($36) first, then the one for this page redrawn large
-- ($3a).  The routine writes the four tiles as [hli]/[hld], a row down, then
-- [hli]/[hl] -- which is why it is a 2x2 block and not a 2x1 strip.
function SummaryMenu:drawPageSquare(tx, ty, large)
  local G = love.graphics
  local px, py = tx * 8, ty * 8
  -- $3a..$3d for the page that is up, $36..$39 for the other two.
  local first = large and TILE_SQUARE_LARGE or TILE_SQUARE_SMALL
  local inset = first == TILE_SQUARE_LARGE and 2 or 5
  local size = 16 - inset * 2
  G.setColor(0, 0, 0, 1)
  G.rectangle("fill", px + inset, py + inset, size, size)
  G.setColor(1, 1, 1, 1)
end

function SummaryMenu:drawPageIndicators()
  local columns = { 13, 15, 17 }
  for i, tx in ipairs(columns) do
    self:drawPageSquare(tx, 5, i == self.page)
  end
end

function SummaryMenu:picImage(path)
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

function SummaryMenu:picFor(mon)
  local def = mon and self.pokemon and self.pokemon[mon.species]
  local path = def and def.spriteFront
  -- StatsScreen_PlaceFrontpic (engine/pokemon/stats_screen.asm:722): `ld hl,
  -- wTempMonDVs / call GetUnownLetter` runs before the frontpic, so a party
  -- Unown's page shows its own form, not letter A.
  if mon and mon.species == Unown.SPECIES then
    path = Unown.formSprite(self.pokemon, Unown.monLetter(mon)) or path
  end
  return self:picImage(path)
end

-- PrepMonFrontpic at hlcoord 0, 0: a 7x7 block with the pic padded into it and
-- the rest of the block left at the palette's colour 0.
function SummaryMenu:drawPicBlock(image, colors)
  if not image then return end
  local G = love.graphics
  -- A fill behind the pic reads a palette colour directly, so it has to come
  -- through GbcPalette.color rather than off the raw table.
  local blank = colors and GbcPalette.color(colors, 1) or { 255, 255, 255 }
  G.setColor(blank[1] / 255, blank[2] / 255, blank[3] / 255, 1)
  G.rectangle("fill", 0, 0, 7 * 8, 7 * 8)

  local wide = math.floor(image:getWidth() / 8)
  local pad = PIC_PAD[wide] or PIC_PAD[7]
  G.setColor(1, 1, 1, 1)
  local function body() G.draw(image, pad[1] * 8, pad[2] * 8) end
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, body)
  else
    body()
  end
  G.setColor(1, 1, 1, 1)
end

function SummaryMenu:drawPic()
  local mon = self.mon
  local image = mon and self:picFor(mon)
  if not image then return end
  local colors = self.palettes and mon.species
    and Palettes.monColors(self.palettes, mon.species, mon.shiny) or nil
  self:drawPicBlock(image, colors)
end

-- EggStatsScreen ends on `hlcoord 0, 0 / call PrepMonFrontpic` as well
-- (engine/pokemon/stats_screen.asm:786), and for an egg wCurPartySpecies is
-- EGG, so GetBaseData's `.egg` arm hands GetFrontpic EggPic at 5x5
-- (home/pokemon.asm:239-245) rather than the hidden hatchling's pic.  That
-- pic has no data.pokemon row of its own: the extractor writes it once as
-- menu_gfx.eggHatch.egg, the same file src/ui/gen2/EggHatchAnim.lua draws.
-- _CGB_StatsScreenHPPals colours it off the EGG palette row for the same
-- reason (`ld a, [wCurPartySpecies] / call GetPlayerOrMonPalettePointer`,
-- engine/gfx/cgb_layouts.asm:177-180), shininess read from the DVs, so a
-- shiny hatchling's egg takes EGG's shiny row.
--
-- A cache built before the extractor grew menu_gfx.eggHatch.egg has no such
-- file, and every cache imported before that stage is one -- which is the
-- whole of "the SUMMARY shows no egg picture": the 7x7 block was simply left
-- blank.  ICON_EGG is in icons.lua all the way back (ReadMonMenuIcon's
-- `cp EGG / jr z, .egg` arm, engine/gfx/mon_icons.asm), so the party list's
-- own egg stands in at 2x rather than the page showing nothing.  It is a
-- fallback, not the layout: a cache with EggPic in it never reaches this.
function SummaryMenu:drawEggPic()
  local gfx = (self.menuGfx or {}).eggHatch
  local colors = Palettes.monColors(self.palettes, "EGG",
    self.mon and self.mon.shiny)
  local image = self:picImage(gfx and gfx.egg)
  if image then return self:drawPicBlock(image, colors) end
  self:drawEggIconFallback(colors)
end

-- The ICON_EGG sheet is two 16x16 frames stacked into one 16x32 image
-- (src/ui/gen2/PartyMenu.lua reads the same entry); the first frame is the
-- egg at rest, which is the one the party list shows while nothing is moving.
function SummaryMenu:drawEggIconFallback(colors)
  local icons = self.icons or {}
  local entry = icons.icons and icons.icons.ICON_EGG
  local image = self:picImage(entry and entry.image)
  if not image then return end
  local G = love.graphics
  local blank = colors and GbcPalette.color(colors, 1) or { 255, 255, 255 }
  G.setColor(blank[1] / 255, blank[2] / 255, blank[3] / 255, 1)
  G.rectangle("fill", 0, 0, 7 * 8, 7 * 8)
  local w = entry.width or 16
  local h = math.min(entry.height or 16, image:getHeight())
  if (entry.frames or 1) > 1 then h = math.floor(h / entry.frames) end
  local ok, quad = pcall(love.graphics.newQuad, 0, 0, w, h,
    image:getWidth(), image:getHeight())
  if not ok then return end
  -- Centred in the block at 2x: a 16x16 icon inside 7x7 tiles.
  local x = math.floor((7 * 8 - w * 2) / 2)
  local y = math.floor((7 * 8 - h * 2) / 2)
  G.setColor(1, 1, 1, 1)
  local function body() G.draw(image, quad, x, y, 0, 2, 2) end
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, body)
  else
    body()
  end
  G.setColor(1, 1, 1, 1)
end

function SummaryMenu:drawPlacements(list)
  for _, entry in ipairs(list) do
    Chrome.print(entry.text, entry.x, entry.y)
  end
end

-- StatsScreen_PlaceHorizontalDivider: twenty $62 cells across row 7.  $62 is
-- FontBattleExtra's empty HP/exp bar cell, so it resolves through the font
-- while useBattleExtra is on.
function SummaryMenu:drawHorizontalDivider()
  love.graphics.setColor(0, 0, 0, 1)
  for x = 0, Chrome.SCREEN_W - 1 do
    Font.drawCode(TILE_HORIZONTAL_DIVIDER, x * 8, 7 * 8)
  end
end

function SummaryMenu:drawVerticalDivider(tx)
  for y = 8, 17 do self:pageTile(TILE_VERTICAL_DIVIDER, tx, y) end
end

function SummaryMenu:drawUpperHalf()
  local mon = self.mon or {}
  self:drawPic()
  self:drawPlacements(self:upperPlacements())
  self:drawHorizontalDivider()
  -- StatsScreen_PlacePageSwitchArrows, then StatsScreen_PlaceShinyIcon.
  Chrome.print("◀", 12, 6)
  Chrome.print("▶", 19, 6)
  if mon.shiny then self:pageTile(TILE_SHINY, 19, 0) end
  self:drawPageIndicators()
end

function SummaryMenu:drawPinkPage()
  local mon = self.mon or {}
  local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 0
  -- DrawPlayerHP is DrawBattleHPBar with d = 6 and b = 0: "HP:" at (0,9), six
  -- bar cells, and the end cap at (8,9) -- which LoadPinkPage then rewrites as
  -- $41, the same shape from the stats sheet.
  if self.hud and self.hud:available() then
    self.hud:drawHpBar(mon.hp, maxHp, 0, 9)
  else
    HpBar.drawWithLabel(self.palettes, mon.hp, maxHp, 0, 9, Font)
  end
  self:drawVerticalDivider(9)
  self:drawPlacements(self:pinkPlacements())

  -- FillInExpBar is handed (11,16), adds 7 to reach the rightmost cell and
  -- fills eight of them walking left, with the $40/$41 caps outside at (10,16)
  -- and (19,16).
  local fraction = HpBar.expFraction(mon, self:growth(), Mon.experienceForLevel)
  if self.hud and self.hud:available() then
    self.hud:drawExpBar(fraction, 11, 16)
  else
    -- No HUD sheet in the cache: the plain rule, which is HP_BAR_LENGTH_PX
    -- (48) wide rather than the exp bar's 64, so it stops two tiles short of
    -- the $41 cap.  A cache old enough to hit this has no bar tiles at all.
    HpBar.drawExp(self.palettes, fraction, 11 * 8, 16 * 8 + 3)
  end
  self:pageTile(TILE_BAR_CAP_LEFT, 10, 16)
  self:pageTile(TILE_BAR_CAP_RIGHT, 19, 16)
end

function SummaryMenu:drawGreenPage()
  self:drawPlacements(self:greenPlacements())
end

function SummaryMenu:drawBluePage()
  self:drawVerticalDivider(10)
  self:drawPlacements(self:bluePlacements())
end

function SummaryMenu:drawMoveDetail()
  local mon = self.mon or {}
  Chrome.clear()
  -- Textbox (0,1) with a 9x18 interior and Textbox (0,11) with a 5x18 one.
  Chrome.textbox(0, 1, 18, 9)
  Chrome.textbox(0, 11, 18, 5)
  -- SetUpMoveScreenBG draws both boxes and only THEN places the nickname at
  -- (5,1) -- the upper box's own top border row -- and PlaceMoveData writes
  -- the TYPE plaque at (0,10)/(0,11), the lower box's top border row.  Those
  -- cells belong to the strings, not to the frames.
  clearCells(5, 1, tiles(monName(mon)) + tiles(levelText(mon.level)), 1)
  clearCells(0, 10, 7, 2)
  -- PlaceMoveScreenLeftArrow / RightArrow only draw when there is a party mon
  -- that way; both sit on row 0, above the list box.
  if self.index > 1 then Chrome.print("◀", 16, 0) end
  if self.index < #self.party then Chrome.print("▶", 18, 0) end
  self:drawPlacements(self:moveDetailPlacements())
  -- MoveScreen2DMenuData: cursor column 1, first row 3, two rows per step.
  local moves = self:moveList()
  if #moves > 0 then
    -- .a_button's PlaceHollowCursor parks a hollow '▷' on the held row.
    if self.swapFrom then
      Chrome.cursor(1, 3 + (math.min(self.swapFrom, #moves) - 1) * 2, true)
    end
    Chrome.cursor(1, 3 + (math.min(self.moveIndex, #moves) - 1) * 2)
  end
end

-- EggStatsScreen's draw: the row-7 divider, the fixed strings, and
-- PrepMonFrontpic over the EGG pic (engine/pokemon/stats_screen.asm:786).
-- The pic comes from menu_gfx.eggHatch.egg, never from the hidden species'
-- battle/front entry, which is why it goes through drawEggPic.
function SummaryMenu:drawEggPage()
  Chrome.clear()
  self:drawEggPic()
  self:drawHorizontalDivider()
  self:drawPlacements(self:eggPlacements())
end

function SummaryMenu:drawPanel()
  -- StatsScreen_LoadFont is _LoadFontsBattleExtra, so $60-$7f on this screen
  -- is the battle sheet: <LV> is the bold ":L" and $62 is the bar cell the
  -- row-7 rule is made of.
  local wasBattle = Font.useBattleExtra(true)
  if isEggMon(self.mon) then
    self:drawEggPage()
  elseif self.moveDetail then
    self:drawMoveDetail()
  else
    Chrome.clear()
    self:drawUpperHalf()
    if self.page == GREEN_PAGE then
      self:drawGreenPage()
    elseif self.page == BLUE_PAGE then
      self:drawBluePage()
    else
      self:drawPinkPage()
    end
  end
  Font.useBattleExtra(wasBattle)
  love.graphics.setColor(1, 1, 1, 1)
end

function SummaryMenu:draw()
  self:drawPanel()
end

function SummaryMenu:drawWidescreen(winW, winH)
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

SummaryMenu.STAT_LABELS = STAT_LABELS
SummaryMenu.STAT_KEYS = STAT_KEYS
SummaryMenu.TYPE_NAMES = TYPE_NAMES
SummaryMenu.levelText = levelText

return SummaryMenu
