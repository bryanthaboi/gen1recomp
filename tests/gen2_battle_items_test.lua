-- The PACK inside a Gen 2 battle: every family engine/items/item_effects.asm
-- can spend on a party mon, driven through the real BattleState:useItem.
--
--   luajit tests/gen2_battle_items_test.lua
--
-- ROM-free.  The HP line already had its own flow (gen2_battle_ui_test pins
-- it); what is asserted here is the rest of UseItem_SelectMon's fan-out --
-- StatusHealingEffect and its berries, ReviveEffect on a fainted BENCHED mon,
-- RestorePPEffect's move pick for the ETHER pair and its no-pick ELIXER pair,
-- BitterBerryEffect's substatus-only cure -- plus the battle-only arm the
-- field routine has no way to reach (HealStatus clearing SUBSTATUS_CONFUSED on
-- whoever is out).
--
-- The tail is the fishing path: FishFunction writes BATTLETYPE_FISH beside the
-- hooked species, which is the single condition LureBallMultiplier reads, so
-- the rod's own encounter is walked end to end and a LURE BALL thrown in it.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 battle items")
require("tests.fixture_data.gen2_engine_flags").bind("gold")
local check, eq = S.check, S.eq

love = require("tests.love_stub")
-- The rod leg puts a real TextBox up over a stub font, which has no glyphs to
-- measure; the warning per character is noise, not a finding.
require("src.core.Logger").warn = function() end

local Battle = require("src.battle.gen2.Battle")
local BattleState = require("src.ui.gen2.BattleState")
local Input = require("src.core.Input")
local Mon = require("src.battle.gen2.Mon")
local MoveDeleter = require("src.ui.gen2.MoveDeleter")
local PackMenu = require("src.ui.gen2.PackMenu")
local PartyMenu = require("src.ui.gen2.PartyMenu")
local World = require("src.world.gen2.World")

-- ---------------------------------------------------------------- fixtures

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  WATER = { id = "WATER", index = 21, category = "special" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, accuracyRaw = 242, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  SCRATCH = { id = "SCRATCH", name = "SCRATCH", power = 40, type = "NORMAL",
    accuracy = 100, accuracyRaw = 255, pp = 35, effect = "EFFECT_NORMAL_HIT" },
}

local GROWTH = {
  GROWTH_MEDIUM_SLOW = { numerator = 6, denominator = 5, squared = -15,
    linear = 100, constant = 140 },
}

local POKEMON = {
  growthRates = GROWTH,
  CYNDAQUIL = {
    id = "CYNDAQUIL", index = 155, name = "CYNDAQUIL",
    baseStats = { hp = 39, attack = 52, defense = 43, speed = 65,
      specialAttack = 60, specialDefense = 50 },
    types = { "NORMAL", "NORMAL" }, catchRate = 45, baseExp = 65,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 31,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  TOTODILE = {
    id = "TOTODILE", index = 158, name = "TOTODILE",
    baseStats = { hp = 50, attack = 65, defense = 64, speed = 43,
      specialAttack = 44, specialDefense = 48 },
    types = { "WATER", "WATER" }, catchRate = 45, baseExp = 66,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 31,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  PIDGEY = {
    id = "PIDGEY", index = 16, name = "PIDGEY",
    baseStats = { hp = 40, attack = 45, defense = 40, speed = 56,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 55,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  MAGIKARP = {
    id = "MAGIKARP", index = 129, name = "MAGIKARP",
    baseStats = { hp = 20, attack = 10, defense = 55, speed = 80,
      specialAttack = 15, specialDefense = 20 },
    types = { "WATER", "WATER" }, catchRate = 45, baseExp = 20,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
}

local function item(id, pocket, name)
  return { id = id, pocket = pocket or "ITEM", name = name or id }
end

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  text = require("tests.fixture_data.gen2_rom_text_s7_g").text(nil, require("tests.gen2_battle_text_fixture")()),
  type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(), types = TYPES, matchups = {} },
  items = {
    POTION = item("POTION"),
    ANTIDOTE = item("ANTIDOTE"),
    BURN_HEAL = item("BURN_HEAL"),
    FULL_HEAL = item("FULL_HEAL"),
    PSNCUREBERRY = item("PSNCUREBERRY"),
    BITTER_BERRY = item("BITTER_BERRY"),
    REVIVE = item("REVIVE"),
    MAX_REVIVE = item("MAX_REVIVE"),
    ETHER = item("ETHER"),
    ELIXER = item("ELIXER"),
    MAX_ELIXER = item("MAX_ELIXER"),
    POKE_BALL = item("POKE_BALL", "BALL", "POKe BALL"),
    LURE_BALL = item("LURE_BALL", "BALL", "LURE BALL"),
    -- The two nibbles of data/items/attributes.asm that disagree, spelled the
    -- way the extractor spells them.
    RARE_CANDY = { id = "RARE_CANDY", pocket = "ITEM", name = "RARE CANDY",
      fieldMenu = "ITEMMENU_PARTY", battleMenu = "ITEMMENU_NOUSE" },
    OLD_ROD = { id = "OLD_ROD", pocket = "KEY", name = "OLD ROD",
      fieldMenu = "ITEMMENU_CURRENT", battleMenu = "ITEMMENU_NOUSE" },
    -- a mod's own battle-pack item: its action lives only in
    -- gen2ItemEffects below, which ItemEffects.RECORDS (the module's
    -- built-in table) has never heard of (#8)
    MOD_ITEM = item("MOD_ITEM"),
  },
  gen2ItemEffects = {
    -- a status cure rather than an HP heal: HP is exposed to the wild
    -- mon's own reply once the item spends the turn, which would make a
    -- direct before/after HP check depend on incidental battle math this
    -- fix has nothing to do with.  Status is not.
    MOD_ITEM = {
      action = "status", field = true, needsTarget = true,
      use = function(ctx)
        local mon = ctx.mon
        if mon.status ~= "poison" then
          return { used = false, text = "It won't have\nany effect." }
        end
        mon.status = nil
        return { used = true, text = "MOD ITEM used!" }
      end,
    },
  },
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

-- The smallest roll that neither crits nor misses, so a spent turn resolves
-- the same way every run.
local function detRandom(n)
  if (n or 1) <= 1 then return 0 end
  return 1
end

local function newScreen(opts)
  opts = opts or {}
  Input:init()
  local pushed = {}
  local player = opts.player or Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  if not player.moves or #player.moves == 0 then
    player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  end
  local party = opts.party or { player }
  local wild = opts.wild or Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
  wild.moves = wild.moves or { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local save = { party = party, inventory = opts.inventory or {} }
  local game = {
    data = DATA,
    save = save,
    input = Input,
    options = {},
    stack = {
      push = function(_, screen) pushed[#pushed + 1] = screen end,
      pop = function() table.remove(pushed) end,
      top = function() return pushed[#pushed] end,
    },
  }
  local battle = Battle.new({ data = DATA, party = party, wild = wild,
    save = save, random = opts.random or detRandom })
  local screen = BattleState.new(game, { battle = battle, save = save })
  return screen, battle, player, save, pushed
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
local function drainItemResult(pushed)
  for _ = 1, 400 do
    local top = pushed[#pushed]
    if not (top and top.itemResult) then return end
    Input:overlayPressed("a")
    Input:step()
    top:update(1 / 60)
    Input:overlayReleased("a")
  end
end

local function pick(pushed, slot, mon)
  local picker = pushed[#pushed]
  picker.onChoose(slot, mon)
  drainItemResult(pushed)
  return picker
end

-- ---- StatusHealingEffect on a BENCHED mon ---------------------------------
do
  local lead = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  lead.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local bench = Mon.new(DATA, "TOTODILE", 8, { dvs = perfect })
  bench.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  bench.status = "poison"
  bench.toxicCounter = 3
  local screen, battle, _, save, pushed = newScreen({
    player = lead, party = { lead, bench },
    inventory = { ANTIDOTE = 2, BURN_HEAL = 1, PSNCUREBERRY = 1 },
  })
  check(runToMenu(screen), "the intro drains to the battle menu")

  local turn0 = battle.turn
  screen:useItem("ANTIDOTE")
  eq(screen.phase, "submenu", "a status cure opens UseItem_SelectMon first")
  local picker = pushed[#pushed]
  eq(getmetatable(picker), PartyMenu, "and the pick is the party screen")
  eq(picker.prompt, PartyMenu.PROMPTS.useItem, "under the cart's own question")
  pick(pushed, 2, bench)
  eq(bench.status, nil, "the ANTIDOTE cured the BENCHED mon")
  eq(bench.toxicCounter, nil, "and the toxic ramp went with the status byte")
  eq(save.inventory.ANTIDOTE, 1, "one ANTIDOTE left the bag")
  eq(battle.turn, turn0 + 1, "a cure that lands spends the turn")
  check(runToMenu(screen), "the enemy's answer drains out")

  -- UseStatusHealer's mask test: a clean mon, or the wrong class of item,
  -- refuses without spending anything.
  local turn1 = battle.turn
  screen:useItem("ANTIDOTE")
  pushed[#pushed].onChoose(2, bench)
  eq(screen.message, "It won't have any\neffect.",
    "a clean target answers the cart's refusal")
  eq(save.inventory.ANTIDOTE, 1, "with the ANTIDOTE still in the bag")
  eq(battle.turn, turn1, "and the turn not spent")
  check(runToMenu(screen), "back to the menu")

  bench.status = "poison"
  screen:useItem("BURN_HEAL")
  pushed[#pushed].onChoose(2, bench)
  eq(screen.message, "It won't have any\neffect.",
    "a BURN HEAL does not answer poison")
  eq(bench.status, "poison", "the status is untouched")
  eq(save.inventory.BURN_HEAL, 1, "and nothing spent")
  check(runToMenu(screen), "back to the menu")

  -- The berries carry the same StatusHealingActions rows as the shop cures.
  screen:useItem("PSNCUREBERRY")
  pick(pushed, 2, bench)
  eq(bench.status, nil, "PSNCUREBERRY cures poison like an ANTIDOTE")
  eq(save.inventory.PSNCUREBERRY, nil, "and the berry is eaten")
  check(runToMenu(screen), "back to the menu")

  -- Backing out of the picker returns to the pack with nothing spent.
  screen:useItem("ANTIDOTE")
  pushed[#pushed].onCancel()
  eq(getmetatable(pushed[#pushed]), PackMenu,
    "cancelling the picker reopens the PACK (.SelectMon's carry path)")
  eq(save.inventory.ANTIDOTE, 1, "with the ANTIDOTE untouched")
end

-- ---- a mod's own battle-pack item (#8) -------------------------------------
-- BattleState:useItem asked ItemEffects.partyAction for the item's family
-- with no `data` argument, the same omission Game2:usePartyItem had for the
-- field pack, so a mod item's action -- present only in the merged
-- gen2ItemEffects table -- resolved to nil and the pack fell straight to
-- "That isn't going to help here." instead of opening the party list.
do
  local sick = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  sick.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  sick.status = "poison"
  local screen, _, _, save, pushed = newScreen({
    player = sick, party = { sick }, inventory = { MOD_ITEM = 1 },
  })
  check(runToMenu(screen), "reached the menu")

  screen:useItem("MOD_ITEM")
  eq(screen.phase, "submenu",
    "a mod's own gen2ItemEffects record opens UseItem_SelectMon")
  local picker = pushed[#pushed]
  eq(getmetatable(picker), PartyMenu, "and the pick is the party screen")
  if picker and picker.onChoose then
    picker.onChoose(1, sick)
    eq(sick.status, nil, "the mod item's own use() ran through the real screens")
    eq(save.inventory.MOD_ITEM, nil, "and the mod item was spent")
  end
end

-- ---- IsItemUsedOnConfusedMon: the battle-only arm --------------------------
do
  local screen, battle, player, save, pushed = newScreen({
    inventory = { FULL_HEAL = 2, ANTIDOTE = 1 },
  })
  check(runToMenu(screen), "reached the menu")

  -- A mon whose only complaint is the confusion volatile: the field routine
  -- refuses (the status byte is clean), the battle one spends the item.
  battle:volatile(player).confuseCount = 3
  local turn0 = battle.turn
  screen:useItem("FULL_HEAL")
  pick(pushed, 1, player)
  eq(battle:volatile(player).confuseCount, nil,
    "a $ff-mask item clears SUBSTATUS_CONFUSED on whoever is out")
  eq(save.inventory.FULL_HEAL, 1, "and it costs the FULL HEAL")
  eq(battle.turn, turn0 + 1, "and the turn")
  check(runToMenu(screen), "the turn drains")

  -- The mask is what gates it: an ANTIDOTE is 1 << PSN, so it answers poison
  -- and leaves the confusion standing.
  player.status = "poison"
  battle:volatile(player).confuseCount = 3
  screen:useItem("ANTIDOTE")
  pick(pushed, 1, player)
  eq(player.status, nil, "the ANTIDOTE still cures the poison")
  eq(battle:volatile(player).confuseCount, 3,
    "but a masked cure leaves the confusion alone")
  check(runToMenu(screen), "back to the menu")

  -- BitterBerryEffect never opens the party list: it acts on the mon that is
  -- out, and one that is not confused refuses.
  save.inventory.BITTER_BERRY = 2
  local depth = #pushed
  screen:useItem("BITTER_BERRY")
  eq(#pushed, depth, "a BITTER BERRY opens no picker")
  eq(battle:volatile(player).confuseCount, nil, "it cured the confusion")
  eq(save.inventory.BITTER_BERRY, 1, "and was eaten doing it")
  check(runToMenu(screen), "the turn drains")

  screen:useItem("BITTER_BERRY")
  eq(screen.message, "It won't have any\neffect.",
    "a clear-headed mon refuses the berry")
  eq(save.inventory.BITTER_BERRY, 1, "with the berry still in the bag")
end

-- ---- ReviveEffect on a fainted BENCHED mon --------------------------------
do
  local lead = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  lead.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local bench = Mon.new(DATA, "TOTODILE", 8, { dvs = perfect })
  bench.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  bench.hp = 0
  bench.status = "faint"
  local screen, battle, _, save, pushed = newScreen({
    player = lead, party = { lead, bench },
    inventory = { REVIVE = 2, MAX_REVIVE = 1 },
  })
  check(runToMenu(screen), "reached the menu")

  -- A healthy target is RevivePokemon's `ret nz`: nothing spent.
  screen:useItem("REVIVE")
  pushed[#pushed].onChoose(1, lead)
  eq(screen.message, "It won't have any\neffect.",
    "a live mon refuses the REVIVE")
  eq(save.inventory.REVIVE, 2, "with both REVIVEs still in the bag")
  check(runToMenu(screen), "back to the menu")

  local maxHp = bench.maxHp or bench.stats.hp
  local turn0 = battle.turn
  screen:useItem("REVIVE")
  pick(pushed, 2, bench)
  eq(bench.hp, math.max(1, math.floor(maxHp / 2)),
    "REVIVE stands the BENCHED mon up at half max HP (ReviveHalfHP)")
  eq(bench.status, nil, "with its status byte cleared")
  eq(save.inventory.REVIVE, 1, "one REVIVE spent")
  eq(battle.turn, turn0 + 1, "and the turn spent with it")
  check(runToMenu(screen), "the turn drains")

  bench.hp = 0
  screen:useItem("MAX_REVIVE")
  pick(pushed, 2, bench)
  eq(bench.hp, maxHp, "MAX REVIVE takes ReviveFullHP instead")
  eq(save.inventory.MAX_REVIVE, nil, "and is spent")
  check(runToMenu(screen), "the turn drains")

  -- The revived mon is a mon again as far as the engine is concerned: it can
  -- be switched to, which is the whole point of reviving mid-battle.
  check(battle:switch(2), "the revived mon can be sent out")
  eq(battle.player, bench, "and it is the one in play")
end

-- ---- RestorePPEffect: the ETHER pick and the ELIXER sweep ------------------
do
  local player = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  player.moves = {
    { id = "TACKLE", pp = 35, maxPp = 35 },
    { id = "SCRATCH", pp = 4, maxPp = 35 },
  }
  local screen, battle, _, save, pushed = newScreen({
    player = player,
    inventory = { ETHER = 2, ELIXER = 1, MAX_ELIXER = 1 },
  })
  check(runToMenu(screen), "reached the menu")

  screen:useItem("ETHER")
  eq(getmetatable(pushed[#pushed]), PartyMenu, "the ETHER picks a mon first")
  pushed[#pushed].onChoose(1, player)
  local moveList = pushed[#pushed]
  eq(getmetatable(moveList), MoveDeleter,
    "then the move list (MoveSelectionScreen shares SetUpMoveList with it)")
  eq(#pushed, 2, "stacked over the party list, which is still standing")

  -- Backing out of the move list drops only that screen, which is
  -- RestorePPEffect's own `jr nz, .loop` back to the pick.
  moveList.onCancel()
  eq(#pushed, 1, "cancelling the move list leaves the party list up")
  eq(getmetatable(pushed[#pushed]), PartyMenu, "on the party list")
  eq(save.inventory.ETHER, 2, "with nothing spent")

  pushed[#pushed].onChoose(1, player)
  local turn0 = battle.turn
  pick(pushed, 2)
  eq(player.moves[2].pp, 14, "the ETHER put 10 PP back into the chosen slot")
  eq(player.moves[1].pp, 35, "and left the other slot alone")
  eq(save.inventory.ETHER, 1, "one ETHER spent")
  eq(battle.turn, turn0 + 1, "and the turn with it")
  check(runToMenu(screen), "the turn drains")

  -- A slot already at max is `cp b / jr nc, .dont_restore`: nothing spent.
  screen:useItem("ETHER")
  pushed[#pushed].onChoose(1, player)
  pushed[#pushed].onChoose(1)
  eq(screen.message, "It won't have any\neffect.",
    "a full slot answers the refusal")
  eq(save.inventory.ETHER, 1, "with the ETHER still in the bag")
  check(runToMenu(screen), "back to the menu")

  -- Elixer_RestorePPofAllMoves needs no pick at all.
  player.moves[1].pp = 30
  player.moves[2].pp = 14
  local depth = #pushed
  screen:useItem("ELIXER")
  pick(pushed, 1, player)
  eq(#pushed, depth, "the ELIXER opened no move list")
  eq(player.moves[1].pp, 35, "it filled the first slot (capped at max)")
  eq(player.moves[2].pp, 24, "and walked on to the second")
  eq(save.inventory.ELIXER, nil, "spending the ELIXER")
  check(runToMenu(screen), "the turn drains")

  screen:useItem("MAX_ELIXER")
  pick(pushed, 1, player)
  eq(player.moves[2].pp, 35, "MAX ELIXER takes the .restore_all arm")
  eq(save.inventory.MAX_ELIXER, nil, "and is spent")
end

-- ---- an EGG refuses every family before anything runs ---------------------
do
  local screen, _, _, save, pushed = newScreen({
    inventory = { ANTIDOTE = 1, REVIVE = 1, ETHER = 1 },
  })
  check(runToMenu(screen), "reached the menu")
  for _, id in ipairs({ "ANTIDOTE", "REVIVE", "ETHER" }) do
    screen:useItem(id)
    pushed[#pushed].onChoose(3, { isEgg = true, hp = 0, maxHp = 12,
      moves = { { id = "TACKLE", pp = 0, maxPp = 35 } } })
    eq(screen.message, "That can't be used\non an EGG.",
      id .. " answers CantUseOnEggMessage")
    eq(save.inventory[id], 1, "and is not spent")
    check(runToMenu(screen), "back to the menu")
  end
end

-- ---- ITEMMENU_NOUSE in a battle is .Oak -----------------------------------
do
  local screen, battle, player, save, pushed = newScreen({
    inventory = { RARE_CANDY = 1, OLD_ROD = 1 },
  })
  check(runToMenu(screen), "reached the menu")
  local level, turn0, depth = player.level, battle.turn, #pushed
  screen:useItem("RARE_CANDY")
  eq(#pushed, depth, "a RARE CANDY opens no party list in a battle")
  eq(player.level, level, "and levels nothing")
  eq(save.inventory.RARE_CANDY, 1, "with the candy still in the bag")
  eq(battle.turn, turn0, "and the turn not spent")

  screen:useItem("OLD_ROD")
  eq(save.inventory.OLD_ROD, 1, "a rod is ITEMMENU_NOUSE in battle too")
end

-- ---- the rod's own battle carries BATTLETYPE_FISH --------------------------
do
  local pushed = {}
  local save = { player = {}, party = {}, inventory = { LURE_BALL = 1,
    POKE_BALL = 1 } }
  local player = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  save.party[1] = player
  -- The rod's line rides a real TextBox, so the world needs an input its
  -- update can read; `press` is the A that turns the page.
  local fakeInput = { pressed = {} }
  function fakeInput:press(button) self.pressed[button] = true end
  function fakeInput:wasPressed(button)
    if self.pressed[button] then
      self.pressed[button] = nil
      return true
    end
    return false
  end
  function fakeInput:isDown() return false end
  local game = {
    data = DATA, save = save, input = fakeInput, options = {},
    stack = {
      push = function(_, screen) pushed[#pushed + 1] = screen end,
      pop = function() table.remove(pushed) end,
      top = function() return pushed[#pushed] end,
    },
  }
  local world = World.new(game)
  -- Script_GotABite's tail, with the state the rod itself left behind: the
  -- hooked mon, the bite bob already served, the rod being put away.  No map
  -- is mounted, so DoBattleTransition has nothing to wipe and the battle comes
  -- straight in, which is the same arm a headless run takes.
  local hooked = Mon.new(DATA, "MAGIKARP", 10, { dvs = perfect })
  hooked.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  world.fishing = { phase = "bite", timer = 0, outcome = "battle",
    wild = hooked }
  world:updateFishing()
  -- RodBiteText is up; A pages it, and its dismissal is what runs startbattle.
  local screen
  for _ = 1, 600 do
    local top = pushed[#pushed]
    if top and getmetatable(top) == BattleState then screen = top break end
    fakeInput:press("a")
    if top and top.update then top:update(1 / 60) end
  end
  eq(world.fishing, nil, "PutTheRodAway clears the rod state before the battle")
  check(screen ~= nil, "the rod's encounter pushed a battle")
  eq(screen.battle.battleType, Battle.BATTLETYPE_FISH,
    "carrying BATTLETYPE_FISH out of FishFunction's .goodtofish")

  -- LureBallMultiplier's x3, through the real throw.  A full-HP MAGIKARP at
  -- catch rate 45 computes to 15; the LURE BALL's tripled rate is 45, so a
  -- fixed roll of 30 catches with one ball and not with the other.
  local function throw(ball, type_)
    Input:init()
    local wild = Mon.new(DATA, "MAGIKARP", 10, { dvs = perfect })
    wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    local lead = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
    lead.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    local bagSave = { party = { lead }, inventory = { [ball] = 1 } }
    local shot = {
      data = DATA, save = bagSave, input = Input, options = {},
      stack = { push = function() end, pop = function() end,
        top = function() return nil end },
    }
    local battle = Battle.new({ data = DATA, party = { lead }, wild = wild,
      save = bagSave, battleType = type_,
      random = function(n) if n == 256 then return 30 end return 0 end })
    local state = BattleState.new(shot, { battle = battle, save = bagSave })
    state:useItem(ball)
    return battle.outcome
  end

  eq(throw("LURE_BALL", screen.battle.battleType), "caught",
    "a LURE BALL thrown in the rod's battle catches on that roll")
  eq(throw("LURE_BALL", nil), nil,
    "the same ball and the same roll off a rod does not")
  eq(throw("POKE_BALL", screen.battle.battleType), nil,
    "and neither does a plain ball in the rod's battle")
end

S.finish()
