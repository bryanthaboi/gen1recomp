-- BattlePack (engine/items/pack.asm:627): the PACK opened from the battle menu
-- is a different jumptable from the field PACK's.
--
--   luajit tests/gen2_battle_pack_test.lua
--
-- ROM-free.  Three things are pinned here, all through the real screens:
--
--   * .Use dispatches on the item's BATTLE menu nibble, and its first four
--     jumptable entries are .Oak -- so a key item picked mid-fight prints
--     OakThisIsntTheTimeText inside the pack.  Nothing on this path may reach
--     the field jumptable: the ITEMFINDER's field arm queues a script and
--     quits the PACK, which over a battle would take the battle off the stack
--     with it and leave the world's battleActive stuck on.
--   * the status names the battle writes and the names the pack's cures read
--     are one contract, walked table against table so a cure can never go
--     missing again (a paralysis the battle spells "paralyze" was uncurable by
--     every bag item there is).
--   * a bag row whose id has no ItemAttributes behind it still draws.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 battle pack")
local check, eq = S.check, S.eq

love = require("tests.love_stub")
-- The pack draws through a stub font with no glyphs; the warning per character
-- is noise, not a finding.
require("src.core.Logger").warn = function() end

local Battle = require("src.battle.gen2.Battle")
local BattleState = require("src.ui.gen2.BattleState")
local Input = require("src.core.Input")
local ItemEffects = require("src.core.gen2.ItemEffects")
local Mon = require("src.battle.gen2.Mon")
local PackMenu = require("src.ui.gen2.PackMenu")
local PartyMenu = require("src.ui.gen2.PartyMenu")
local World = require("src.world.gen2.World")

-- ---------------------------------------------------------------- fixtures

local TYPES = { NORMAL = { id = "NORMAL", index = 0, category = "physical" } }

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, accuracyRaw = 242, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  -- The move id and the printed name differ, which is the whole reason the TM
  -- row resolves one to the other.
  ROCK_SMASH = { id = "ROCK_SMASH", name = "ROCK SMASH", power = 20,
    type = "NORMAL", accuracy = 100, accuracyRaw = 255, pp = 15,
    effect = "EFFECT_DEFENSE_DOWN_HIT" },
}

local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
}

local POKEMON = {
  growthRates = GROWTH,
  CYNDAQUIL = {
    id = "CYNDAQUIL", index = 155, name = "CYNDAQUIL",
    baseStats = { hp = 39, attack = 52, defense = 43, speed = 65,
      specialAttack = 60, specialDefense = 50 },
    types = { "NORMAL", "NORMAL" }, catchRate = 45, baseExp = 65,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 31,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  PIDGEY = {
    id = "PIDGEY", index = 16, name = "PIDGEY",
    baseStats = { hp = 40, attack = 45, defense = 40, speed = 56,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "FLYING" }, catchRate = 255, baseExp = 55,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
}

-- The attribute pairs as data/items/attributes.asm carries them: the two
-- nibbles disagree for exactly the items this suite is about.
local ITEMS = {
  POTION = { id = "POTION", index = 17, name = "POTION", pocket = "ITEM",
    fieldMenu = "ITEMMENU_PARTY", battleMenu = "ITEMMENU_PARTY" },
  PARLYZ_HEAL = { id = "PARLYZ_HEAL", index = 20, name = "PARLYZ HEAL",
    pocket = "ITEM", fieldMenu = "ITEMMENU_PARTY",
    battleMenu = "ITEMMENU_PARTY" },
  FULL_HEAL = { id = "FULL_HEAL", index = 21, name = "FULL HEAL",
    pocket = "ITEM", fieldMenu = "ITEMMENU_PARTY",
    battleMenu = "ITEMMENU_PARTY" },
  PRZCUREBERRY = { id = "PRZCUREBERRY", index = 22, name = "PRZCUREBERRY",
    pocket = "ITEM", fieldMenu = "ITEMMENU_PARTY",
    battleMenu = "ITEMMENU_PARTY" },
  MIRACLEBERRY = { id = "MIRACLEBERRY", index = 23, name = "MIRACLEBERRY",
    pocket = "ITEM", fieldMenu = "ITEMMENU_PARTY",
    battleMenu = "ITEMMENU_PARTY" },
  POKE_BALL = { id = "POKE_BALL", index = 5, name = "POKe BALL",
    pocket = "BALL", fieldMenu = "ITEMMENU_NOUSE",
    battleMenu = "ITEMMENU_CLOSE" },
  ITEMFINDER = { id = "ITEMFINDER", index = 55, name = "ITEMFINDER",
    pocket = "KEY_ITEM", fieldMenu = "ITEMMENU_CLOSE",
    battleMenu = "ITEMMENU_NOUSE" },
  -- The trophy boxes live in the ITEMS pocket on the cart, not with the key
  -- items, and are NOUSE in battle like every other decoration.
  NORMAL_BOX = { id = "NORMAL_BOX", index = 167, name = "NORMAL BOX",
    pocket = "ITEM", fieldMenu = "ITEMMENU_CURRENT",
    battleMenu = "ITEMMENU_NOUSE" },
  TM_ROCK_SMASH = { id = "TM_ROCK_SMASH", index = 198, name = "TM08",
    pocket = "TM_HM", teaches = "ROCK_SMASH", tmNumber = 8,
    fieldMenu = "ITEMMENU_PARTY", battleMenu = "ITEMMENU_NOUSE" },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  text = require("tests.fixtures.gen2_rom_text").text(require("tests.fixture_data.gen2_rom_text_s7_g").text(nil, require("tests.gen2_battle_text_fixture")())),
  gen2Text = require("tests.fixtures.gen2_common_text").text(),
  gen2EventTables = require("tests.fixtures.gen2_phone_events").events,
  type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(), types = TYPES, matchups = {} },
  items = ITEMS,
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

-- The smallest roll that neither crits nor misses.
local function detRandom(n)
  if (n or 1) <= 1 then return 0 end
  return 1
end

-- A battle over a LIVE overworld, which is the shape the bug needed: World
-- keeps battleActive set for as long as the BattleState is on the stack, and
-- game.world is what PackMenu falls back to when a caller passes no world.
local function newBattleOverWorld(inventory)
  Input:init()
  local player = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local wild = Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local save = { party = { player }, inventory = inventory or {},
    player = { name = "GOLD" } }
  local pushed = {}
  local game = {
    data = DATA, save = save, input = Input, options = {},
    stack = {
      push = function(_, screen) pushed[#pushed + 1] = screen end,
      pop = function() table.remove(pushed) end,
      top = function() return pushed[#pushed] end,
      clear = function(self) while #pushed > 0 do self:pop() end end,
    },
  }
  local world = World.new(game)
  world.player = { cellX = 5, cellY = 5, facing = "down" }
  world.map = { id = "ROUTE_29", def = {} }
  world.battleActive = true
  game.world = world
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    save = save, random = detRandom })
  local screen = BattleState.new(game, { battle = battle, save = save })
  game.stack:push(screen)
  return screen, battle, world, save, pushed, player
end

-- Battle lines end in `prompt`, and PromptButton waits on A or B with no
-- frame countdown (home/joypad.asm:383-412), so a drain has to press like a
-- player does rather than wait for a timer that never runs out.
local function runToMenu(screen, cap)
  for _ = 1, (cap or 3000) do
    local waiting = (screen.messageTimer or 0) > 0
    if waiting then Input:overlayPressed("a") end
    Input:step()
    screen:update(1 / 60)
    if waiting then Input:overlayReleased("a") end
    if screen.phase == "menu" then return true end
  end
  return false
end

-- engine/items/item_effects.asm:1748
local function pick(pushed, slot, mon)
  local picker = pushed[#pushed]
  picker.onChoose(slot, mon)
  for _ = 1, 400 do
    local top = pushed[#pushed]
    if not (top and top.itemResult) then break end
    Input:overlayPressed("a")
    Input:step()
    top:update(1 / 60)
    Input:overlayReleased("a")
  end
  return picker
end

-- The real menu press: the 2x2 grid's DOWN puts the cursor on PACK.
local function openPackFromMenu(screen, pushed)
  Input:overlayPressed("down")
  Input:step()
  screen:update(1 / 60)
  Input:overlayReleased("down")
  Input:step()
  eq(BattleState.MENU_ACTION[screen.menuIndex], "item", "the cursor is on PACK")
  Input:overlayPressed("a")
  Input:step()
  screen:update(1 / 60)
  Input:overlayReleased("a")
  Input:step()
  return pushed[#pushed]
end

local function pressPack(pack, button)
  Input:overlayPressed(button)
  Input:step()
  pack:update(1 / 60)
  Input:overlayReleased(button)
  Input:step()
end

-- ---- the battle PACK never runs a field effect ----------------------------
-- ItemSubmenu (engine/items/pack.asm:783
do
  local screen, _, world, save, pushed = newBattleOverWorld({
    POTION = 2, ITEMFINDER = 1, NORMAL_BOX = 1, TM_ROCK_SMASH = 1 })
  check(runToMenu(screen), "the intro drains to the battle menu")
  local pack = openPackFromMenu(screen, pushed)
  eq(getmetatable(pack), PackMenu, "PACK opens the pack")
  eq(pack:inBattle(), true, "as BattlePack rather than the field Pack")
  eq(pack:hasSubmenu(), true, "which has ItemSubmenu on the cart")
  eq(#pushed, 2, "over the battle, which is still on the stack")

  -- KEY ITEMS, where the arm that ate the battle lived.
  pressPack(pack, "right")
  pressPack(pack, "right")
  eq(pack:pocket().id, "KEY_ITEM", "right twice reaches the KEY ITEMS pocket")

  pack.index = 1
  eq(pack.rows[1].id, "ITEMFINDER", "the ITEMFINDER is the first row")
  pressPack(pack, "a")
  check(pack.submenu ~= nil, "A on it opens the submenu")
  eq(table.concat(pack.submenu.rows, ","), "quit",
    "a battle-NOUSE key item gets .UnusableMenuHeader's lone QUIT")
  eq(pack.message, nil, "with no Oak line anywhere near it")
  eq(#pushed, 2, "the pack is still up")
  eq(pushed[1], screen, "and the battle is still under it")
  eq(world.battleActive, true, "the world is still in its battle")
  eq(world.queuedScript, nil, "no field script was queued")
  eq(save.inventory.ITEMFINDER, 1, "and the key item is still in the bag")

  pressPack(pack, "a")
  eq(pack.submenu, nil, "QUIT closes the submenu")
  eq(pack.message, nil, "printing nothing")
  eq(save.inventory.ITEMFINDER, 1, "and still spending nothing")

  -- The trophy boxes are the same nibble: no decoration flag, no box spent.
  pressPack(pack, "left")
  pressPack(pack, "left")
  eq(pack:pocket().id, "ITEM", "back in the ITEMS pocket")
  pack.index = 2
  eq(pack.rows[2].id, "NORMAL_BOX", "with the trophy box in it")
  pressPack(pack, "a")
  eq(pack.submenu and table.concat(pack.submenu.rows, ","), "quit",
    "a trophy box gets the QUIT-only submenu too")
  eq(save.inventory.NORMAL_BOX, 1, "the box is not spent")
  eq(next(world.events.flags or {}), nil, "and no decoration flag was granted")
  pressPack(pack, "b")
  eq(pack.submenu, nil, "B backs out of it as well")

  pressPack(pack, "right")
  pressPack(pack, "right")
  pressPack(pack, "right")
  eq(pack:pocket().id, "TM_HM", "the TM pocket")
  pack.index = 1
  eq(pack.rows[1].id, "TM_ROCK_SMASH", "with the TM in it")
  pressPack(pack, "a")
  eq(pack.submenu and table.concat(pack.submenu.rows, ","), "quit",
    "a TM in a fight gets QUIT alone")
  eq(table.concat(pack:submenuRows("MYSTERY_THING"), ","), "quit",
    "and so does a row with no attributes behind it, `xor a` forcing it")
  pressPack(pack, "b")

  pressPack(pack, "left")
  pressPack(pack, "left")
  pressPack(pack, "left")
  eq(pack:pocket().id, "ITEM", "back in the ITEMS pocket")
  pack.index = 1
  eq(pack.rows[1].id, "POTION", "on the POTION")
  pressPack(pack, "a")
  eq(pack.submenu and table.concat(pack.submenu.rows, ","), "use,quit",
    "a battle-legal item gets .UsableMenuHeader's USE / QUIT")
  eq(pack.submenu.index, 1, "opening on USE (`db 1 ; default option`)")
  eq(getmetatable(pushed[#pushed]), PackMenu, "and nothing is used yet")
  pressPack(pack, "a")
  eq(getmetatable(pushed[#pushed]), PartyMenu,
    "USE opens UseItem_SelectMon")
end

-- engine/items/pack.asm:1068
do
  local save = { player = { name = "GOLD" },
    inventory = { POKE_BALL = 1 } }
  local game = { data = DATA, save = save, input = Input, options = {},
    stack = { push = function() end, pop = function() end,
      top = function() return nil end } }
  local thrown
  local pack = PackMenu.new(game, {
    save = save, items = ITEMS, world = {}, pocket = "BALL",
    battle = true, tutorial = true,
    onChoose = function(id) thrown = id end,
  })
  eq(pack:inBattle(), true, "the DUDE's pack is opened over a battle")
  eq(pack:hasSubmenu(), false, "and still has no submenu")
  pressPack(pack, "a")
  eq(pack.submenu, nil, "so A opens nothing")
  eq(thrown, "POKE_BALL", "and throws the ball on the first press")
end

-- ../pokecrystal/engine/items/pack.asm:810
-- two headers in ../pokegold/engine/items/pack.asm are menu_coords 0.
do
  local Chrome = require("src.ui.gen2.Chrome")
  local realBox = Chrome.box
  local realCursor = Chrome.cursorThrough
  local realPrint = Chrome.printThrough
  local boxes = {}
  Chrome.box = function(tx, ty, tw, th) boxes[#boxes + 1] = { tx, ty, tw, th } end
  Chrome.cursorThrough = function() end
  Chrome.printThrough = function() end

  local function battlePack(version)
    local save = { player = { name = "GOLD" }, version = version,
      inventory = { POTION = 1 } }
    local game = { data = DATA, save = save, input = Input, options = {},
      stack = { push = function() end, pop = function() end,
        top = function() return nil end } }
    return PackMenu.new(game, { save = save, items = ITEMS, world = {},
      pocket = "ITEM", battle = true })
  end

  local function drawnBox(pack)
    pressPack(pack, "a")
    boxes = {}
    pack:drawSubmenu()
    return boxes[1]
  end

  local gold = battlePack("gold")
  eq(gold:submenuColumn(), 0, "Gold's battle submenu is menu_coords 0")
  local goldBox = drawnBox(gold)
  eq(goldBox and goldBox[1], 0, "and the box it draws starts in column 0")
  eq(goldBox and goldBox[3], 7, "SCREEN_WIDTH - 14 wide, both borders in")
  eq(goldBox and goldBox[2], 7, ".UsableMenuHeader's row 7")

  local crystal = battlePack("crystal")
  eq(crystal:submenuColumn(), 13, "Crystal's is menu_coords 13")
  local crystalBox = drawnBox(crystal)
  eq(crystalBox and crystalBox[1], 13, "putting the same box on the right")
  eq(crystalBox and crystalBox[3], 7, "SCREEN_WIDTH - 1 is the same 7 wide")

  local silver = battlePack("silver")
  eq(silver:submenuColumn(), 0, "Silver runs Gold's engine and its column")

  -- ../pokecrystal/engine/items/pack.asm:313 is menu_coords 13, 1, ...,
  -- TEXTBOX_Y - 1 and ../pokegold/engine/items/pack.asm:313 is
  local function fieldPack(version)
    local save = { player = { name = "GOLD" }, version = version,
      inventory = { POTION = 1 } }
    local game = { data = DATA, save = save, input = Input, options = {},
      stack = { push = function() end, pop = function() end,
        top = function() return nil end } }
    return PackMenu.new(game, { save = save, items = ITEMS })
  end

  local function fiveRowBox(pack)
    pack.submenu = { rows = { "use", "give", "toss", "sel", "quit" }, index = 1 }
    boxes = {}
    pack:drawSubmenu()
    return boxes[1]
  end

  local crystalField = fieldPack("crystal")
  eq(crystalField:submenuColumn(), 13, "Crystal's field submenu is menu_coords 13")
  local crystalFieldBox = fiveRowBox(crystalField)
  eq(crystalFieldBox and crystalFieldBox[1], 13, "off the pack picture, on the right")
  eq(crystalFieldBox and crystalFieldBox[2], 1, "MenuHeader_UsableKeyItem's row 1")
  eq(crystalFieldBox and crystalFieldBox[4], 11, "eleven rows to TEXTBOX_Y - 1")

  local goldField = fieldPack("gold")
  eq(goldField:submenuColumn(), 0, "Gold's field submenu stays at menu_coords 0")
  local goldFieldBox = fiveRowBox(goldField)
  eq(goldFieldBox and goldFieldBox[1], 0, "over the pack picture, on the left")
  eq(goldFieldBox and goldFieldBox[2], 2, "one row lower: menu_coords 0, 2")
  eq(goldFieldBox and goldFieldBox[4], 11, "the same eleven rows, to TEXTBOX_Y")

  local silverField = fieldPack("silver")
  eq(silverField:submenuColumn(), 0, "Silver runs Gold's engine in the field too")

  Chrome.box = realBox
  Chrome.cursorThrough = realCursor
  Chrome.printThrough = realPrint
end

-- ---- and the world refuses both arms on its own ---------------------------
do
  local _, _, world, save = newBattleOverWorld({ ITEMFINDER = 1,
    NORMAL_BOX = 1 })
  eq(world:useItemfinder(), "nowhere",
    "World:useItemfinder refuses while a battle is up")
  eq(world.queuedScript, nil, "queueing nothing")
  eq(world:openTrophyBox("NORMAL_BOX"), "nowhere",
    "World:openTrophyBox refuses too")
  eq(save.inventory.NORMAL_BOX, 1, "with the box still in the bag")

  -- The same two answer normally once the battle is over, so the gate is the
  -- battle and not the item.
  world.battleActive = nil
  eq(world:useItemfinder(), "itemfinder",
    "and in the field the ITEMFINDER still quits the PACK")
  check(world.queuedScript ~= nil, "with its script queued")
  eq(world:openTrophyBox("NORMAL_BOX"), "trophy_sent",
    "and the trophy box still sends its trophy home")
  eq(save.inventory.NORMAL_BOX, nil, "spending the box")
end

-- ---- status names: one contract between the battle and the pack -----------
do
  -- Every name Battle can write into mon.status has to resolve to a heal
  -- class, or the cure for it refuses everywhere.
  local written = {}
  for _, status in pairs(Battle.STATUS_EFFECTS) do written[status] = true end
  for _, status in pairs(Battle.SECONDARY_EFFECTS) do written[status] = true end
  for _, status in pairs(Battle.HELD_STATUS_CURES) do written[status] = true end
  for status in pairs(Battle.STATUS_TEXT) do written[status] = true end
  -- Confusion is SUBSTATUS_CONFUSED, not a status byte: BitterBerryEffect and
  -- the $ff-mask arm of HealStatus own it, and neither reads STATUS_CLASS.
  written.confuse = nil

  local missing = {}
  for status in pairs(written) do
    if not ItemEffects.STATUS_CLASS[status] then
      missing[#missing + 1] = status
    end
  end
  table.sort(missing)
  eq(#missing, 0, "every status the battle writes has a heal class ("
    .. table.concat(missing, ", ") .. ")")
  eq(ItemEffects.STATUS_CLASS.paralyze, "par",
    "including the paralysis spelling the engine actually writes")

  -- And back the other way: every class a spelling folds to must be a class
  -- some StatusHealingActions row asks for.
  local cured = { all = true }
  for _, class in pairs(ItemEffects.HEAL_STATUS) do cured[class] = true end
  local orphan = {}
  for spelling, class in pairs(ItemEffects.STATUS_CLASS) do
    if not cured[class] then orphan[#orphan + 1] = spelling end
  end
  eq(#orphan, 0, "no spelling folds to a class no item cures ("
    .. table.concat(orphan, ", ") .. ")")
end

-- ---- the paralysis cure, through both packs -------------------------------
do
  -- The battle is what writes the byte: EFFECT_PARALYZE lands "paralyze".
  local screen, battle, _, save, pushed, player = newBattleOverWorld({
    PARLYZ_HEAL = 1, FULL_HEAL = 1, PRZCUREBERRY = 1, MIRACLEBERRY = 1 })
  check(runToMenu(screen), "reached the battle menu")
  battle:applyStatus(player, Battle.STATUS_EFFECTS.EFFECT_PARALYZE)
  eq(player.status, "paralyze", "BattleCommand_Paralyze writes 'paralyze'")

  local turn0 = battle.turn
  screen:useItem("PARLYZ_HEAL")
  pick(pushed, 1, player)
  eq(player.status, nil, "a PARLYZ HEAL cures it in battle")
  eq(save.inventory.PARLYZ_HEAL, nil, "the item is spent")
  eq(battle.turn, turn0 + 1, "and the turn with it")
  check(runToMenu(screen), "the enemy's answer drains out")

  -- The three other rows that carry the same class, on the field routine the
  -- overworld PACK runs (ItemEffects.useOnMon is the whole of it).
  for _, itemId in ipairs({ "FULL_HEAL", "PRZCUREBERRY", "MIRACLEBERRY" }) do
    local mon = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
    mon.status = "paralyze"
    local result = ItemEffects.useOnMon(itemId, mon, DATA)
    eq(result.used, true, itemId .. " cures paralysis in the field")
    eq(mon.status, nil, "and clears the byte")
  end

  -- The refusal is still there for a mon that has nothing to cure.
  local clean = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  local refused = ItemEffects.useOnMon("PARLYZ_HEAL", clean, DATA)
  eq(refused.used, false, "a clean mon still refuses the cure")
end

-- ---- a bag row with no attributes behind it -------------------------------
do
  local save = { player = { name = "GOLD" },
    inventory = { POTION = 2, MYSTERY_THING = 3, LEGACY_KEY = true,
      TM_ROCK_SMASH = 1 } }
  local game = { data = DATA, save = save, input = Input, options = {},
    stack = { push = function() end, pop = function() end,
      top = function() return nil end } }
  local pack = PackMenu.new(game, {})
  local byId = {}
  for _, row in ipairs(pack.rows) do byId[row.id] = row end
  eq(byId.MYSTERY_THING and byId.MYSTERY_THING.name, "MYSTERY THING",
    "an unknown id stands in for its own name")
  eq(byId.MYSTERY_THING and byId.MYSTERY_THING.count, 3, "keeping its count")
  eq(byId.LEGACY_KEY and byId.LEGACY_KEY.count, 1,
    "and a count that is not a number counts as one")
  eq(pack:pocketOf("MYSTERY_THING"), "ITEM",
    "with no pocket to read, it lands in the general pocket")
  pack.index = 2
  eq(pack:description(), nil, "it has no description to print")
  pack.gfx = { available = function() return true end, draw = function() end,
    colorsAt = function() return nil end }
  local ok, err = pcall(function() pack:drawPanel() end)
  check(ok, "and the pocket still draws (" .. tostring(err) .. ")")

  -- The TM pocket's second line is GetMoveName's string, not the move id: an
  -- id would print an underscore the font has no glyph for.
  pack:switchPocket(3)
  eq(pack:pocket().id, "TM_HM", "the TM pocket")
  eq(pack.rows[1] and pack.rows[1].name, "TM08", "lists the TM by its label")
  eq(pack.rows[1] and pack.rows[1].teaches, "ROCK SMASH",
    "with the move's NAME under it")
end

-- ---- the PACK's cursor bytes live across openings -------------------------
--
-- Each pocket menu restores its own cursor and scroll before ScrollingMenu and
-- writes them back after (engine/items/pack.asm:76), and InitPackBuffers opens
-- the PACK on wLastPocket.  CleanUpBattleRAM is the only thing that clears
-- them, and its list pointedly leaves the TM/HM pair alone
-- (engine/battle/core.asm:7994-8004).
do
  local screen, battle, _, save, pushed = newBattleOverWorld({
    POTION = 2, SUPER_POTION = 1, POKE_BALL = 3, ITEMFINDER = 1, TM08 = 1 })
  check(runToMenu(screen), "the intro drains to the battle menu")
  -- The 2x2 cursor stays where it was left, so walk it onto PACK each time.
  local function openPack()
    while BattleState.MENU_ACTION[screen.menuIndex] ~= "item" do
      Input:overlayPressed("down")
      Input:step()
      screen:update(1 / 60)
      Input:overlayReleased("down")
      Input:step()
      screen:update(1 / 60)
    end
    Input:overlayPressed("a")
    Input:step()
    screen:update(1 / 60)
    Input:overlayReleased("a")
    Input:step()
    screen:update(1 / 60)
    return pushed[#pushed]
  end
  local pack = openPack()
  eq(getmetatable(pack), PackMenu, "PACK opens the pack")
  pressPack(pack, "down")
  eq(pack.index, 2, "the cursor moved to the second row")
  pressPack(pack, "b") -- back out of the PACK
  eq(screen.phase, "menu", "B gives the battle menu back")

  local reopened = openPack()
  eq(reopened.index, 2, "and the PACK reopens on the row it was left on")
  eq(reopened:pocket().id, "ITEM", "in the pocket it was left in")

  -- wLastPocket: the pocket is remembered too.
  pressPack(reopened, "right")
  eq(reopened:pocket().id, "BALL", "right reaches the BALL pocket")
  pressPack(reopened, "down")
  eq(reopened.index, 2, "with its own row")
  pressPack(reopened, "b")
  local third = openPack()
  eq(third:pocket().id, "BALL", "wLastPocket reopens on the BALL pocket")
  eq(third.index, 2, "on its own remembered row")
  -- And the ITEM pocket kept the row it was left on, separately.
  pressPack(third, "left")
  eq(third:pocket().id, "ITEM", "back to ITEMS")
  eq(third.index, 2, "which still has its own cursor")
  pressPack(third, "b")

  -- CleanUpBattleRAM clears the ITEM / KEY_ITEM / BALL bytes and wLastPocket.
  battle.over = true
  battle.outcome = "win"
  screen:finishBattle()
  local game = screen.game
  eq(game.packCursor.pocket, nil, "wLastPocket is zeroed at the end of a battle")
  eq(game.packCursor.cursor.ITEM, nil, "and the ITEM pocket's cursor with it")
  eq(game.packCursor.cursor.BALL, nil, "and the BALL pocket's")
  eq(save.inventory.POTION, 2, "with the bag untouched")
end

-- The TM/HM pair is NOT in CleanUpBattleRAM's list, so it survives a battle.
do
  local screen, battle, _, _, pushed = newBattleOverWorld({ TM08 = 1,
    POTION = 1 })
  check(runToMenu(screen), "the intro drains to the battle menu")
  local pack = openPackFromMenu(screen, pushed)
  pack:switchPocket(3)
  eq(pack:pocket().id, "TM_HM", "the TM pocket")
  pack.index = 2
  pack:storeCursor()
  pressPack(pack, "b")
  battle.over = true
  battle.outcome = "win"
  screen:finishBattle()
  eq(screen.game.packCursor.cursor.TM_HM, 2,
    "the TM/HM cursor is not in ExitBattle's clear list")
end

S.finish()
