-- The Gen 2 battle screen against the cart's own HUD and pacing rules:
-- minimum damage out of BattleCommand_DamageCalc's tail, the -6/+6 stat stage
-- wall, the HP bar chase (engine/battle/anim_hp_bar.asm), the status tag in
-- the level's spot (PlaceNonFaintStatus), BattleMenu's empty textbox, the
-- intro slide's one-piece back pic, and ItemRestoreHP's pick-a-mon flow.
--
--   GOLD_CACHE="..." luajit tests/gen2_battle_ui_test.lua
--
-- ROM-free: fixtures below are the extractor's shapes; the one cache-fed
-- section (the GROWL animation's cry) skips cleanly when there is no cache.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 battle ui")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Battle = require("src.battle.gen2.Battle")
local BattleAnimView = require("src.ui.gen2.BattleAnimView")
local BattleState = require("src.ui.gen2.BattleState")
local Damage = require("src.battle.gen2.Damage")
local Input = require("src.core.Input")
local Mon = require("src.battle.gen2.Mon")
local PackMenu = require("src.ui.gen2.PackMenu")
local PartyMenu = require("src.ui.gen2.PartyMenu")
local Sound = require("src.core.Sound")

-- ---------------------------------------------------------------- fixtures

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  FLYING = { id = "FLYING", index = 2, category = "physical" },
  GROUND = { id = "GROUND", index = 4, category = "physical" },
  ROCK = { id = "ROCK", index = 5, category = "physical" },
  FIRE = { id = "FIRE", index = 20, category = "special" },
  WATER = { id = "WATER", index = 21, category = "special" },
  ELECTRIC = { id = "ELECTRIC", index = 23, category = "special" },
}

local MATCHUPS = {
  { attacker = "NORMAL", defender = "ROCK", multiplier = 5 },
  { attacker = "FIRE", defender = "WATER", multiplier = 5 },
  { attacker = "ELECTRIC", defender = "GROUND", multiplier = 0 },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  GROWL = { id = "GROWL", name = "GROWL", power = 0, type = "NORMAL",
    accuracy = 100, pp = 40, effect = "EFFECT_ATTACK_DOWN" },
  THUNDER_WAVE = { id = "THUNDER_WAVE", name = "THUNDERWAVE", power = 0,
    type = "ELECTRIC", accuracy = 100, pp = 20, effect = "EFFECT_PARALYZE" },
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
    types = { "FIRE", "FIRE" }, catchRate = 45, baseExp = 65,
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
    types = { "NORMAL", "FLYING" }, catchRate = 255, baseExp = 55,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  GEODUDE = {
    id = "GEODUDE", index = 74, name = "GEODUDE",
    baseStats = { hp = 40, attack = 80, defense = 100, speed = 20,
      specialAttack = 30, specialDefense = 30 },
    types = { "ROCK", "GROUND" }, catchRate = 255, baseExp = 73,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 31,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  type_chart = { types = TYPES, matchups = MATCHUPS },
  items = {
    -- `index` is the ROM item id, which is what wBattleAnimParam carries.
    MASTER_BALL = { id = "MASTER_BALL", pocket = "BALL", name = "MASTER BALL",
      index = 1 },
    POKE_BALL = { id = "POKE_BALL", pocket = "BALL", name = "POKe BALL",
      index = 5 },
    FAST_BALL = { id = "FAST_BALL", pocket = "BALL", name = "FAST BALL",
      index = 160 },
    POTION = { id = "POTION", pocket = "ITEM", name = "POTION" },
  },
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

-- Deterministic and range-respecting: the smallest roll that is neither a
-- critical hit (rollCritical wants 0) nor a miss.
local function detRandom(n)
  if (n or 1) <= 1 then return 0 end
  return 1
end

-- ---- DamageCalc's minimum (engine/battle/effect_commands.asm) -------------
do
  -- Stats weak enough that the raw formula floors to 0: the cart still walks
  -- out of DamageCalc with MIN_DAMAGE (2).
  local weak = Damage.calc({
    level = 5, power = 35, moveType = "NORMAL",
    attacker = { attack = 6, types = { "FIRE" } },
    defender = { defense = 40, types = { "WATER" } },
    types = TYPES, matchups = MATCHUPS, variation = 100,
  })
  eq(weak, Damage.MIN_DAMAGE,
    "a hit whose stat math floors to nothing still deals MIN_DAMAGE")

  -- The same hit into a resist: BattleCommand_Stab's zero-quotient arm forces
  -- the row's floor back up to 1, so not-very-effective never reads 0.
  local resisted = Damage.calc({
    level = 5, power = 35, moveType = "NORMAL",
    attacker = { attack = 6, types = { "FIRE" } },
    defender = { defense = 40, types = { "ROCK" } },
    types = TYPES, matchups = MATCHUPS, variation = 100,
  })
  check(resisted >= 1, "a resisted hit that lands deals at least 1")
  local _, info = Damage.calc({
    level = 5, power = 35, moveType = "NORMAL",
    attacker = { attack = 6, types = { "FIRE" } },
    defender = { defense = 40, types = { "ROCK" } },
    types = TYPES, matchups = MATCHUPS, variation = 100,
  })
  eq(info.effectiveness, 5, "and still reports not-very-effective")

  -- Immunity is the one zero left: the row's multiplier IS 0.
  local immune = Damage.calc({
    level = 50, power = 95, moveType = "ELECTRIC",
    attacker = { specialAttack = 100, types = { "ELECTRIC" } },
    defender = { specialDefense = 50, types = { "GROUND" } },
    types = TYPES, matchups = MATCHUPS, variation = 100,
  })
  eq(immune, 0, "an immune matchup still deals nothing at all")
end

-- ---- the same minimum through the real turn engine ------------------------
do
  local player = Mon.new(DATA, "CYNDAQUIL", 5, { dvs = perfect })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local wild = Mon.new(DATA, "GEODUDE", 5, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = detRandom })
  local before = wild.hp
  local events = battle:takeTurn({ kind = "move", move = "TACKLE" })
  local dealt, sawNve = nil, false
  for _, event in ipairs(events) do
    if event.kind == "damage" and event.side == "enemy" and not dealt then
      dealt = event.amount
    end
    if event.kind == "message"
        and event.text == "It's not very effective..." then
      sawNve = true
    end
  end
  check(sawNve, "TACKLE into GEODUDE reads as not very effective")
  check((dealt or 0) >= 1, "and the landed hit dealt at least 1 HP, not 0")
  eq(wild.hp, before - dealt, "with the HP moving by exactly that much")
end

-- ---- the -6 stage wall (BattleCommand_StatDown's .CantLower) --------------
do
  local player = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  player.moves = { { id = "GROWL", pp = 40, maxPp = 40 } }
  player.hp = 200
  player.maxHp = 200
  local wild = Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = detRandom })
  for turn = 1, 6 do
    battle:takeTurn({ kind = "move", move = "GROWL" })
    eq(battle.stages.enemy.attack, -turn,
      "GROWL " .. turn .. " lands one stage")
  end
  local events = battle:takeTurn({ kind = "move", move = "GROWL" })
  eq(battle.stages.enemy.attack, -6, "the seventh GROWL moves nothing")
  local refused = false
  for _, event in ipairs(events) do
    if event.kind == "message"
        and event.text == "PIDGEY's ATTACK won't drop anymore!" then
      refused = true
    end
  end
  check(refused, "and the cart's refusal line is emitted instead")

  -- The stage -6 multiplier is 25/100 with a floor of 1: a stat can shrink to
  -- a quarter but never to zero.
  eq(Damage.applyStage(11, -6), math.max(1, math.floor(11 * 25 / 100)),
    "stage -6 is a quarter of the stat")
  eq(Damage.applyStage(1, -6), 1, "and never zero")
  eq(Damage.applyStage(11, -9), Damage.applyStage(11, -6),
    "stages below -6 read as -6")
end

-- ---- BattleState with a stub game -----------------------------------------

local function newScreen(opts)
  opts = opts or {}
  Input:init()
  local pushed = {}
  local player = opts.player
    or Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  if not player.moves or #player.moves == 0 then
    player.moves = {
      { id = "TACKLE", pp = 35, maxPp = 35 },
      { id = "THUNDER_WAVE", pp = 20, maxPp = 20 },
    }
  end
  local party = opts.party or { player }
  local wild = opts.wild or Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
  wild.moves = wild.moves or { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local save = { party = party, inventory = opts.inventory
    or { POTION = 2, POKE_BALL = 3 } }
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
    random = detRandom })
  local screen = BattleState.new(game, { battle = battle, save = save })
  return screen, battle, player, wild, save, pushed
end

local function run(screen, frames)
  for _ = 1, frames do
    Input:step()
    screen:update(1 / 60)
  end
end

-- One frame of a drain.  Battle lines end in `prompt` and PromptButton waits
-- on A or B with no countdown (home/joypad.asm:383-412); the stats box waits
-- the same way (engine/battle/core.asm:7069), so a drain presses rather than
-- idling for a timer that never runs out.
local function drainStep(screen)
  local waiting = (screen.messageTimer or 0) > 0 or screen.phase == "stats-box"
  if waiting then Input:overlayPressed("a") end
  Input:step()
  screen:update(1 / 60)
  if waiting then Input:overlayReleased("a") end
end

local function runToMenu(screen, cap)
  for _ = 1, (cap or 3000) do
    drainStep(screen)
    if screen.phase == "menu" then return true end
  end
  return false
end

do
  local screen = newScreen({ inventory = {
    MASTER_BALL = 1, POKE_BALL = 1,
  } })
  eq(screen:catchChance("MASTER_BALL"), 100,
    "the battle screen exposes a certain Master Ball preview")
  check(type(screen:catchChance("POKE_BALL")) == "number",
    "the battle screen exposes the live wild catch preview")
end

-- ---- BattleMenu empties the textbox ---------------------------------------
do
  local screen = newScreen()
  eq(screen.shownHp.enemy, screen.battle.enemy.hp,
    "the bar opens on the real HP")
  check(runToMenu(screen), "the intro drains to the battle menu")
  eq(screen.message, nil,
    "BattleMenu runs EmptyBattleTextbox: no prompt beside the 2x2 menu")
end

-- ---- the HP bar chase -----------------------------------------------------
do
  local screen, battle, player, wild = newScreen()
  check(runToMenu(screen), "reached the menu")
  local shown0 = screen.shownHp.enemy
  eq(shown0, wild.hp, "the enemy bar sits on the wild mon's real HP")

  screen:submit({ kind = "move", move = "TACKLE" })
  check(wild.hp < shown0, "the engine has already resolved the whole turn")
  eq(screen.shownHp.enemy, shown0,
    "but the drawn bar has not spoiled it: it still shows the pre-turn HP")

  local sawIntermediate = false
  for _ = 1, 3000 do
    Input:step()
    screen:update(1 / 60)
    local shown = screen.shownHp.enemy
    if shown < shown0 and shown > wild.hp then sawIntermediate = true end
    if screen.phase == "menu" then break end
  end
  eq(screen.phase, "menu", "the turn drains back to the menu")
  check(sawIntermediate,
    "the bar walked down through the middle values, one tick a frame")
  eq(screen.shownHp.enemy, wild.hp, "and settled on the real enemy HP")
  eq(screen.shownHp.player, player.hp,
    "the player's bar caught its own hit too")
end

-- ---- the drain is sized by the mon whose bar is ON SCREEN -----------------
do
  -- wCurHPAnimMaxHP is loaded from the battle struct of the mon being drawn
  -- (wEnemyMonMaxHP -> wHPBuffer1, engine/battle/effect_commands.asm:3399-3404),
  -- and after a faint that is still the OUTGOING mon: the engine rebinds
  -- battle.enemy inside takeTurn, a whole queue before the replacement's
  -- `send` event is dequeued.
  local screen, battle = newScreen()
  check(runToMenu(screen), "reached the menu")
  local outgoing = { maxHp = 240, hp = 240 }
  local replacement = { maxHp = 24, hp = 24 }
  screen.shownMon.enemy = outgoing
  battle.enemy = replacement
  screen.shownHp.enemy = 240
  screen.hpAnim = { side = "enemy", to = 0 }
  local ticks = 0
  while screen.hpAnim and ticks < 400 do
    screen:stepHpAnim()
    ticks = ticks + 1
  end
  eq(screen.shownHp.enemy, 0, "the outgoing mon's bar drained to zero")
  eq(ticks, 240 / math.ceil(240 / 48),
    "one PIXEL a tick out of the OUTGOING mon's 240 max HP, not one hit "
    .. "point a tick out of the replacement's 24")
end

-- ---- the exp bar crawls, and the level waits for it -----------------------
do
  -- AnimateExpBar (engine/battle/core.asm:7191) runs BEFORE the exp is
  -- committed and walks the bar one pixel at a time, topping out at 64 and
  -- restarting at 0 for each level crossed, with wBattleMonLevel advanced only
  -- as each segment fills (:7267-7274).
  local player = Mon.new(DATA, "CYNDAQUIL", 5, { dvs = perfect })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local growth = DATA.pokemon.growthRates.GROWTH_MEDIUM_SLOW
  -- One point short of level 6, so whatever the kill pays levels the mon.
  player.experience = Mon.experienceForLevel(growth, 6) - 1
  local wild = Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  wild.hp = 1
  local screen = newScreen({ player = player, wild = wild })
  check(runToMenu(screen), "reached the menu")
  eq(screen.shownLevel, 5, "the HUD opens on the mon's real level")
  local startExp = screen.shownExp
  check(startExp > 0 and startExp < 64,
    "and on its real place along the bar (CalcExpBar's 64 pixels)")

  screen:submit({ kind = "move", move = "TACKLE" })
  eq(wild.hp, 0, "the wild mon went down on the first TACKLE")
  eq(player.level, 6, "and the engine has already levelled the player")
  eq(screen.shownLevel, 5,
    "but the HUD still prints the pre-kill level, several boxes before the "
    .. "grew-to-level line")
  eq(screen.shownExp, startExp, "and the bar has not moved yet either")

  local crawled, restarted = false, false
  for _ = 1, 3000 do
    drainStep(screen)
    if screen.shownLevel == 5 and (screen.shownExp or 0) > startExp then
      crawled = true
    end
    if screen.shownLevel == 6 and (screen.shownExp or 0) == 0 then
      restarted = true
    end
    if screen.phase == "done" then break end
  end
  eq(screen.phase, "done", "the win drains out")
  check(crawled, "the bar walked up through the middle pixels")
  check(restarted,
    "topped out, took the level with it and restarted the segment at 0")
  eq(screen.shownLevel, player.level, "the HUD level caught up")
  eq(screen.shownExp,
    screen:expPixels(player, player.level, player.experience),
    "and the bar landed on the mon's real place in level 6")
end

-- ---- a level-up REDRAWS the HP bar, it does not animate it ----------------
do
  -- GiveExperiencePoints' `.skip_active_mon_update` guard
  -- (engine/battle/core.asm:6999-7003) copies the recalculated HP and max HP
  -- into the battle struct for the mon that is OUT and calls UpdatePlayerHUD
  -- (:7034), which DRAWS the bar rather than chasing it.
  local player = Mon.new(DATA, "CYNDAQUIL", 5, { dvs = perfect })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local growth = DATA.pokemon.growthRates.GROWTH_MEDIUM_SLOW
  player.experience = Mon.experienceForLevel(growth, 6) - 1
  local wild = Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  wild.hp = 1
  local screen = newScreen({ player = player, wild = wild })
  check(runToMenu(screen), "reached the menu")
  local maxBefore = player.maxHp
  screen:submit({ kind = "move", move = "TACKLE" })
  for _ = 1, 3000 do
    drainStep(screen)
    if screen.phase == "done" then break end
  end
  check(player.maxHp > maxBefore, "the level-up raised the maximum")
  eq(screen.shownHp.player, player.hp,
    "and the bar carries the HP the level-up added, without waiting for the "
    .. "next damage or heal event")
end

-- ---- the status tag takes the level's spot --------------------------------
do
  local screen, battle, _, wild = newScreen()
  check(runToMenu(screen), "reached the menu")
  screen:submit({ kind = "move", move = "THUNDER_WAVE" })
  eq(wild.status, "paralyze", "THUNDER WAVE paralyzed the wild mon")
  eq(screen:statusTag(wild), "PAR",
    "so the enemy HUD wears PAR where the level was")
  eq(screen:statusTag({ status = "poison" }), "PSN", "PSN for poison")
  eq(screen:statusTag({ status = "toxic" }), "PSN",
    "toxic wears the same PSN bit")
  eq(screen:statusTag({ status = "burn" }), "BRN", "BRN for burn")
  eq(screen:statusTag({ status = "freeze" }), "FRZ", "FRZ for freeze")
  eq(screen:statusTag({ status = "sleep" }), "SLP", "SLP for sleep")
  eq(screen:statusTag({ status = "confuse" }), nil,
    "confusion is a substatus on the cart and shows no tag")
  eq(screen:statusTag({}), nil, "no status, no tag: the level prints")
end

-- ---- the intro slide's one-piece back pic ---------------------------------
do
  -- CopyBackpic's OAM copy crosses 144px in the 72 frames, 2 a frame.
  eq(BattleAnimView.slideBackpicOffset(0), 144,
    "the back pic starts just off the right edge")
  eq(BattleAnimView.slideBackpicOffset(36), 72, "halfway at frame 36")
  eq(BattleAnimView.slideBackpicOffset(72), 0, "and lands on its column")
  local top, middle = BattleAnimView.slideOffsets(72)
  eq(top, 0, "the enemy band finishes in place")
  eq(middle, 0, "so does the player band")

  -- While the bands are baked, the player-side pic is withheld from them and
  -- drawn only by the overlay, so it cannot tear at the $40 boundary.
  local screen = newScreen()
  screen.slidingBackpic = true
  local ok = pcall(screen.drawPic, screen, screen.battle.player, true)
  check(ok, "drawPic returns cleanly while the overlay owns the back pic")
end

-- ---- ItemRestoreHP: pick a mon, heal that mon -----------------------------
do
  local lead = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  lead.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local bench = Mon.new(DATA, "TOTODILE", 8, { dvs = perfect })
  bench.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  bench.hp = bench.hp - 15
  local screen, battle, _, _, save, pushed =
    newScreen({ player = lead, party = { lead, bench } })
  check(runToMenu(screen), "reached the menu")

  local turn0 = battle.turn
  screen:useItem("POTION")
  eq(screen.phase, "submenu", "a healing item opens a submenu, not a heal")
  local picker = pushed[#pushed]
  eq(getmetatable(picker), PartyMenu,
    "and the submenu is the party screen (UseItem_SelectMon)")
  eq(picker.prompt, PartyMenu.PROMPTS.useItem,
    "asking the cart's own question")

  local benchBefore = bench.hp
  picker.onChoose(2, bench)
  eq(bench.hp, math.min(bench.maxHp or bench.stats.hp, benchBefore + 20),
    "the POTION landed on the BENCHED mon")
  eq(save.inventory.POTION, 1, "and one POTION left the bag")
  eq(battle.turn, turn0 + 1, "a heal that lands spends the turn")
  check(runToMenu(screen), "the enemy's answer drains out")

  -- A full-HP target refuses without costing the item or the turn
  -- (IsMonAtFullHealth's arm of ItemRestoreHP).
  local turn1 = battle.turn
  screen:useItem("POTION")
  pushed[#pushed].onChoose(2, bench)
  eq(screen.message, "It won't have any\neffect.",
    "a full-HP target answers the cart's refusal")
  eq(save.inventory.POTION, 1, "with the POTION still in the bag")
  eq(battle.turn, turn1, "and the turn not spent")
  check(runToMenu(screen), "back to the menu")

  -- An egg is refused before the health check (UseItem_SelectMon .not_egg).
  screen:useItem("POTION")
  pushed[#pushed].onChoose(3, { isEgg = true, hp = 1, maxHp = 12 })
  eq(screen.message, "That can't be used\non an EGG.",
    "an EGG answers CantUseOnEggMessage")
  eq(save.inventory.POTION, 1, "still nothing spent")
  check(runToMenu(screen), "back to the menu")

  -- Backing out of the picker returns to the pack with nothing spent.
  screen:useItem("POTION")
  pushed[#pushed].onCancel()
  eq(getmetatable(pushed[#pushed]), PackMenu,
    "cancelling the picker reopens the PACK (.SelectMon's carry path)")
  eq(save.inventory.POTION, 1, "with the POTION untouched")
end

-- ---- BattleMenu_PKMN opens BattleMonMenu over the list --------------------
do
  -- `callfar BattleMonMenu`, then SWITCH -> TryPlayerSwitch, CANCEL ->
  -- .Cancel -> BattleMenu (engine/battle/core.asm:4810-4816); the voluntary
  -- list is PARTYMENUACTION_CHOOSE_POKEMON and the forced one
  -- PARTYMENUACTION_SWITCH (:4795, :2702).
  local lead = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  lead.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local bench = Mon.new(DATA, "TOTODILE", 8, { dvs = perfect })
  bench.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local screen, battle, _, _, _, pushed =
    newScreen({ player = lead, party = { lead, bench } })
  check(runToMenu(screen), "reached the menu")

  check(screen:openParty(), "the voluntary list opens")
  local list = pushed[#pushed]
  eq(list.prompt, PartyMenu.PROMPTS.choose, "asking ChooseAMonString")
  check(list.wantsBattleSubmenu, "and it carries BattleMonMenu")
  list.index = 2
  list:openSubmenu()
  eq(#list.submenu.items, 3, "BattleMonMenu has three rows")
  eq(list.submenu.items[1].id, "SWITCH", "SWITCH first")
  eq(list.submenu.items[2].id, "STATS", "then STATS")
  eq(list.submenu.items[3].id, "CANCEL", "then CANCEL")

  -- CANCEL leaves the list entirely and lands back on the battle menu.
  list.submenu.index = 3
  list:updateSubmenu({ wasPressed = function(_, b) return b == "a" end })
  eq(screen.phase, "menu", ".Cancel returns to BattleMenu")

  -- SWITCH takes the pick through to the engine.
  check(screen:openParty(), "the list reopens")
  local list2 = pushed[#pushed]
  list2.index = 2
  list2:openSubmenu()
  list2:updateSubmenu({ wasPressed = function(_, b) return b == "a" end })
  check(runToMenu(screen), "the switch drains back to the menu")
  eq(battle.player, bench, "SWITCH reached TryPlayerSwitch")

  -- BattleText_MonIsAlreadyOut, and the turn is NOT spent (:4863-4870).
  local turn0 = battle.turn
  check(screen:openParty(), "the list opens again")
  local list3 = pushed[#pushed]
  list3.index = 2
  list3:openSubmenu()
  list3:updateSubmenu({ wasPressed = function(_, b) return b == "a" end })
  eq(screen.phase, "refuse-switch", "the mon already out is refused")
  check((screen.message or ""):find("is already out"),
    "with BattleText_MonIsAlreadyOut")
  eq(battle.turn, turn0, "and no turn is spent on it")

  -- The forced list is PickPartyMonInBattle: WhichPKMNString, no submenu.
  check(screen:openParty(true), "the forced list opens")
  local forced = pushed[#pushed]
  eq(forced.prompt, PartyMenu.PROMPTS.which, "asking WhichPKMNString")
  eq(forced.wantsBattleSubmenu, false, "with no BattleMonMenu over it")
end

-- ---- SHIFT offers a free swap when the trainer sends its next mon ---------
do
  -- EnemySwitch's shift arm: OfferSwitch, then the enemy's send-out, then
  -- `jp PlayerSwitch` with both participant bitfields zeroed
  -- (engine/battle/core.asm:2941-2963); CheckWhetherToAskSwitch reads the
  -- BATTLE_SHIFT bit CLEAR as SHIFT (:3269-3295).
  local function shiftScreen(style)
    Input:init()
    local pushed = {}
    local lead = Mon.new(DATA, "CYNDAQUIL", 30, { dvs = perfect })
    lead.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    local bench = Mon.new(DATA, "TOTODILE", 30, { dvs = perfect })
    bench.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    local foe1 = Mon.new(DATA, "PIDGEY", 3, { dvs = perfect })
    foe1.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    local foe2 = Mon.new(DATA, "GEODUDE", 3, { dvs = perfect })
    foe2.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    local party = { lead, bench }
    local save = { party = party, inventory = {} }
    local game = {
      data = DATA, save = save, input = Input,
      options = { battleStyle = style },
      stack = {
        push = function(_, screen) pushed[#pushed + 1] = screen end,
        pop = function() table.remove(pushed) end,
        top = function() return pushed[#pushed] end,
      },
    }
    local battle = Battle.new({ data = DATA, party = party, random = detRandom,
      trainer = { class = "FALKNER", name = "FALKNER", party = { foe1, foe2 } } })
    local screen = BattleState.new(game, { battle = battle, save = save })
    return screen, battle, party, pushed
  end

  local function runToPhase(screen, phase, cap)
    for _ = 1, (cap or 4000) do
      drainStep(screen)
      if screen.phase == phase then return true end
    end
    return false
  end

  -- SET never asks (`bit BATTLE_SHIFT, a / jr nz, .return_nc`, :3280-3282).
  local setScreen, setBattle = shiftScreen("SET")
  check(runToMenu(setScreen), "the SET battle reaches its menu")
  setBattle.enemy.hp = 1
  setScreen:submit({ kind = "move", move = "TACKLE" })
  check(runToMenu(setScreen), "the KO drains without stopping")
  eq(setScreen.phase, "menu", "SET is never offered a shift")

  -- SHIFT stops on the prompt before the enemy's send-out line.
  local noScreen, noBattle, noParty = shiftScreen("SHIFT")
  check(runToMenu(noScreen), "the SHIFT battle reaches its menu")
  noBattle.enemy.hp = 1
  local noTurn = noBattle.turn
  noScreen:submit({ kind = "move", move = "TACKLE" })
  -- The `para` in BattleText_EnemyIsAboutToUseWillPlayerChangeMon splits the
  -- offer (data/text/battle.asm:222-231): the incoming mon is named on an
  -- earlier page, and only the last one carries the yes/no box (#1158).
  check(runToPhase(noScreen, "shift-intro"), "the KO stops on OfferSwitch")
  check((noScreen.message or ""):find("is about to use"),
    "with BattleText_EnemyIsAboutToUseWillPlayerChangeMon")
  check(runToPhase(noScreen, "ask-shift"), "and its pages reach the question")
  check((noScreen.message or ""):find("change POK"),
    "whose last page is the one YesNoBox opens over")

  -- NO falls through to the send-out with nothing switched and nothing spent.
  noScreen.messageTimer = 0
  noScreen.shiftIndex = 2
  Input:overlayPressed("a")
  Input:step()
  noScreen:update(1 / 60)
  Input:overlayReleased("a")
  check(runToMenu(noScreen), "NO drains back to the menu")
  eq(noBattle.player, noParty[1], "the lead is still out")
  eq(noBattle.turn, noTurn + 1, "and only the attacking turn was spent")

  -- YES picks a mon, and the switch lands AFTER the enemy's send-out.
  local yesScreen, yesBattle, yesParty, pushed = shiftScreen("SHIFT")
  check(runToMenu(yesScreen), "the second SHIFT battle reaches its menu")
  yesBattle.enemy.hp = 1
  yesScreen:submit({ kind = "move", move = "TACKLE" })
  check(runToPhase(yesScreen, "ask-shift"), "it stops on OfferSwitch too")
  yesScreen.messageTimer = 0
  yesScreen.shiftIndex = 1
  Input:overlayPressed("a")
  Input:step()
  yesScreen:update(1 / 60)
  Input:overlayReleased("a")
  eq(yesScreen.phase, "submenu", "YES opens PickSwitchMonInBattle")
  local picker = pushed[#pushed]
  eq(picker.prompt, PartyMenu.PROMPTS.which, "asking WhichPKMNString")
  eq(picker.wantsBattleSubmenu, false, "with no BattleMonMenu over it")
  picker.onChoose(2, yesParty[2])
  check(runToMenu(yesScreen), "the shift drains back to the menu")
  eq(yesBattle.player, yesParty[2], "the picked mon is out")
  eq(yesBattle.participants[1], nil,
    "and both participant bitfields were zeroed first")
  eq(yesBattle.participants[2], true, "leaving only the incoming slot")
end

-- ---- healing the active mon refills its bar on screen ---------------------
do
  local screen, battle, player = newScreen()
  check(runToMenu(screen), "reached the menu")
  -- Take a hit so there is something to refill.
  screen:submit({ kind = "move", move = "TACKLE" })
  check(runToMenu(screen), "first exchange drains")
  check(player.hp < (player.maxHp or player.stats.hp),
    "the player took damage")
  eq(screen.shownHp.player, player.hp, "and the bar followed it down")

  local screenSave = screen.save
  screenSave.inventory.POTION = 1
  screen:useItem("POTION")
  local picker = screen.game.stack.top()
  picker.onChoose(1, player)
  check(screen.hpAnim ~= nil and screen.hpAnim.side == "player",
    "healing the ACTIVE mon arms the bar chase (HealHP_SFX_GFX's AnimateHPBar)")
  check(runToMenu(screen), "the heal turn drains")
  eq(screen.shownHp.player, player.hp, "and the bar refilled to the new HP")
end

-- ---- GROWL's sound comes from its own anim script (cache-fed) -------------
do
  local cache = os.getenv("GOLD_CACHE")
  if not cache then
    local home = os.getenv("HOME") or ""
    cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
  end
  local path = cache .. "/data/generated/battle_anims.lua"
  local file = io.open(path, "r")
  if not file then
    check(true, "no Gold cache at " .. path .. " (SKIP)")
  else
    file:close()
    local anims = assert(loadfile(path))()
    if not (anims.scripts and anims.moves and anims.moves.GROWL) then
      check(true, "battle_anims.lua has no GROWL script (SKIP)")
    else
      local AnimRunner = require("src.battle.gen2.AnimRunner")
      local constants =
        assert(loadfile(cache .. "/data/generated/constants.lua"))()
      local cried, sounds = nil, 0
      local runner = AnimRunner.new({
        data = anims,
        constants = constants,
        battleTurn = 0,
        animId = "GROWL",
        hooks = {
          cry = function(side, pitch, length) cried = side end,
          sound = function() sounds = sounds + 1 end,
        },
      })
      runner:start(anims.moves.GROWL)
      local frames = 0
      while runner:step() and frames < 600 do frames = frames + 1 end
      -- BattleAnim_Growl (data/moves/animations.asm): `anim_cry $0` plays the
      -- USER's cry, which is the move's whole sound.
      eq(cried, "player", "GROWL's script asks for the user's own cry")
      check(frames > 0 and frames < 600, "and the script terminates")

      -- The chain the SCREEN's cry hook walks, end to end: the same GROWL
      -- script through BattleState:animForMove must reach Sound.playCry with
      -- the user's SPECIES, because audio.cries is keyed by species (the
      -- def.cry field the hook once read does not exist in a Gen 2 cache).
      local audio = assert(loadfile(cache .. "/data/generated/audio.lua"))()
      check(audio.cries and audio.cries.CYNDAQUIL ~= nil,
        "audio.lua keys the cries by species")
      local screen = newScreen()
      screen.game.data.gen2BattleAnims = anims
      screen.game.data.gen2Constants = constants
      screen.game.data.audio = audio
      screen.anims = anims
      screen.animConstants = constants
      check(runToMenu(screen), "reached the menu with the anim runtime live")
      local Sound = require("src.core.Sound")
      local realPlayCry = Sound.playCry
      local played = nil
      Sound.playCry = function(_, species) played = species end
      check(screen:animForMove("GROWL", "player"),
        "the extracted GROWL animation starts")
      for _ = 1, 600 do
        if not screen.anim then break end
        Input:step()
        screen:update(1 / 60)
      end
      Sound.playCry = realPlayCry
      eq(screen.anim, nil, "the animation ran out")
      eq(played, "CYNDAQUIL",
        "and GROWL played the user's cry through Sound.playCry")
    end
  end
end

-- ---- the cursor bytes that live across menu openings ----------------------
--
-- MoveSelectionScreen seeds wMenuCursorY from wCurMoveNum + 1
-- (engine/battle/core.asm:5111) and the A-press writes the picked row back, so
-- the FIGHT list reopens on the move used last turn.  SendOutPlayerMon
-- (core.asm:3809) is what zeroes it, together with wBattleMenuCursorPosition.
do
  local lead = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  lead.moves = { { id = "TACKLE", pp = 35, maxPp = 35 },
    { id = "THUNDER_WAVE", pp = 20, maxPp = 20 } }
  local screen = newScreen({ player = lead })
  check(runToMenu(screen), "reached the menu")
  local function tap(button)
    Input:overlayPressed(button)
    Input:step()
    screen:update(1 / 60)
    Input:overlayReleased(button)
    Input:step()
    screen:update(1 / 60)
  end
  tap("a") -- FIGHT
  eq(screen.phase, "moves", "A on FIGHT opens the move list")
  tap("down")
  eq(screen.moveIndex, 2, "down moves onto the second move")
  tap("a")
  check(runToMenu(screen), "the turn drains back to the menu")
  eq(screen.moveIndex, 2, "wCurMoveNum survived the turn")
  tap("a")
  eq(screen.phase, "moves", "FIGHT reopens")
  eq(screen.moveIndex, 2, "on the move used last turn, not on the first")

  -- A moveset that shrank clamps rather than pointing past the end.
  tap("b")
  screen.moveIndex = 4
  screen.battle.player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  tap("a")
  eq(screen.phase, "moves", "FIGHT opens again")
  eq(screen.moveIndex, 1, "and the row is clamped to the moves that are left")
end

-- SendOutPlayerMon zeroes both cursor bytes, so a switched-in mon opens on
-- FIGHT and on its first move.
do
  local lead = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  lead.moves = { { id = "TACKLE", pp = 35, maxPp = 35 },
    { id = "GROWL", pp = 40, maxPp = 40 } }
  local bench = Mon.new(DATA, "TOTODILE", 8, { dvs = perfect })
  bench.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local screen = newScreen({ player = lead, party = { lead, bench } })
  check(runToMenu(screen), "reached the menu")
  screen.menuIndex = 3
  screen.moveIndex = 2
  screen:submit({ kind = "switch", index = 2 })
  check(runToMenu(screen), "the switch resolves back to the menu")
  eq(screen.menuIndex, 1, "wBattleMenuCursorPosition is back on FIGHT")
  eq(screen.moveIndex, 1, "and wCurMoveNum on the first move")
end

-- ---- no HUD rides in with the intro bands ---------------------------------
--
-- InitBattleDisplay blanks the whole tilemap before BattleIntroSlidingPics
-- (core.asm:8554/8564); UpdateEnemyHUD runs only after BattleStartMessage
-- returns (:7815) and UpdatePlayerHUD at the tail of SendOutPlayerMon (:3838).
do
  local screen = newScreen()
  eq(screen.showEnemyHud, false, "the enemy HUD does not exist at construction")
  eq(screen.showPlayerHud, false, "nor the player's")
  run(screen, BattleAnimView.SLIDE_FRAMES)
  eq(screen.showEnemyHud, false, "and neither rode in with the bands")
  eq(screen.showPlayerHud, false, "on either side")
  -- The appeared line is read against an empty HUD area.
  for _ = 1, 3000 do
    Input:step()
    screen:update(1 / 60)
    if screen.message == "Wild PIDGEY appeared!" then break end
  end
  eq(screen.message, "Wild PIDGEY appeared!", "BattleStartMessage's own line")
  eq(screen.showEnemyHud, false, "with no enemy HUD under it yet")
  check(runToMenu(screen), "the intro drains to the menu")
  eq(screen.showEnemyHud, true, "UpdateEnemyHUD has run by the menu")
  eq(screen.showPlayerHud, true, "and UpdatePlayerHUD after the send-out")
end

-- ---- the wild mon cries with BattleStartMessage ----------------------------
--
-- `.not_shiny`: `ld a, [wTempEnemyMonSpecies] / call PlayStereoCry` runs before
-- WildPokemonAppearedText (engine/battle/core.asm:8718-8721).
do
  local screen = newScreen()
  local realAudio = screen.game.data.audio
  screen.game.data.audio = { cries = { PIDGEY = { pitch = 0 } } }
  local realPlayCry = Sound.playCry
  local played
  Sound.playCry = function(_, species) played = species end
  for _ = 1, 3000 do
    Input:step()
    screen:update(1 / 60)
    if screen.message == "Wild PIDGEY appeared!" then break end
  end
  Sound.playCry = realPlayCry
  screen.game.data.audio = realAudio
  eq(played, "PIDGEY", "the wild mon cries with its appeared line")
end

-- ---- the message box's two fixed rows -------------------------------------
--
-- LineChar reloads the cursor at TEXTBOX_INNERY + 2 (home/text.asm:397), so a
-- two-line battle string sits on rows 14 and 16 with row 15 blank.
do
  local Chrome = require("src.ui.gen2.Chrome")
  local screen = newScreen()
  local realPrint = Chrome.print
  local rows = {}
  Chrome.print = function(text, tx, ty) rows[#rows + 1] = { text, tx, ty } end
  screen.message = "CYNDAQUIL used TACKLE on the wild PIDGEY!"
  screen:printMessage()
  Chrome.print = realPrint
  check(#rows >= 2, "a long line wraps onto a second row")
  eq(rows[1][2], 1, "TEXTBOX_INNERX is column 1")
  eq(rows[1][3], 14, "TEXTBOX_INNERY is row 14")
  eq(rows[2][3], 16, "and LineChar's row is 16, not 15")
  eq(#rows, 2, "with no third row: Paragraph clears only 14-16")
end

-- ---- PokeBallEffect's throw --------------------------------------------
do
  local screen = newScreen()
  -- `cp POKE_BALL + 1 / jr c, .not_kurt_ball / ld a, POKE_BALL`.
  eq(screen:ballAnimParam("MASTER_BALL"), 1, "MASTER BALL throws as itself")
  eq(screen:ballAnimParam("POKE_BALL"), 5, "so does a POKe BALL")
  eq(screen:ballAnimParam("FAST_BALL"), 5,
    "and a Kurt ball throws with POKE_BALL's param")
  -- data/battle_anims/ball_colors.asm.
  eq(screen:ballPalette("MASTER_BALL"), "PAL_BATTLE_OB_GREEN", "green")
  eq(screen:ballPalette("POKE_BALL"), "PAL_BATTLE_OB_RED", "red")
  eq(screen:ballPalette("FAST_BALL"), "PAL_BATTLE_OB_BLUE", "blue")
  eq(screen:ballPalette("NEST_BALL"), "PAL_BATTLE_OB_GRAY",
    "and anything off the table takes the terminator row's gray")

  -- GetPokeBallWobble: three wobbles, then the verdict.
  screen.battle.random = function() return 0 end
  screen.ballThrow = { caught = true, rate = 255, wobble = 0 }
  eq(screen:pokeballWobble(), 0, "a caught mon wobbles once")
  eq(screen:pokeballWobble(), 0, "twice")
  eq(screen:pokeballWobble(), 0, "three times")
  eq(screen:pokeballWobble(), 1, "and the fourth call is the click")

  screen.ballThrow = { caught = false, rate = 255, wobble = 0 }
  eq(screen:pokeballWobble(), 0, "a doomed throw can still wobble")
  eq(screen:pokeballWobble(), 0, "and again")
  eq(screen:pokeballWobble(), 0, "and again")
  eq(screen:pokeballWobble(), 2, "before it breaks free on the fourth")
  eq(screen:ballFailureText(), "Shoot! It was so close too!",
    "four wobbles is BallSoCloseText")

  -- A roll that never comes in under the probability breaks free at once.
  screen.battle.random = function(n) return (n or 256) - 1 end
  screen.ballThrow = { caught = false, rate = 1, wobble = 0 }
  eq(screen:pokeballWobble(), 2, "the first wobble already fails")
  eq(screen:ballFailureText(), "Oh no! The POKéMON broke free!",
    "one wobble is BallBrokeFreeText")
  screen.ballThrow = { caught = false, rate = 1, wobble = 3 }
  eq(screen:ballFailureText(), "Aargh! Almost had it!",
    "three is BallAlmostHadItText")
end

-- ---- a full party sends the catch to the PC, and a full box refuses -------
do
  -- `.SendToPC` / `predef SendMonIntoBox` (engine/items/item_effects.asm:548).
  local party = {}
  for i = 1, 6 do
    local mon = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
    mon.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    party[i] = mon
  end
  local screen, battle, _, wild, save =
    newScreen({ player = party[1], party = party,
      inventory = { MASTER_BALL = 1 } })
  check(runToMenu(screen), "reached the menu")
  screen:useItem("MASTER_BALL")
  eq(battle.outcome, "caught", "the Master Ball catch lands")
  eq(#save.party, 6, "the party is untouched")
  eq((save.boxes and save.boxes[1] or {})[1], wild,
    "and the catch went into the current box, not into nothing")

  -- Ball_BoxIsFullMessage: party full AND box full refuses the throw outright
  -- and reports the item unused, so neither the ball nor the turn goes
  -- (item_effects.asm:217-226).
  local party2 = {}
  for i = 1, 6 do
    local mon = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
    mon.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    party2[i] = mon
  end
  local screen2, battle2, _, _, save2 =
    newScreen({ player = party2[1], party = party2,
      inventory = { MASTER_BALL = 1 } })
  save2.boxes = { {} }
  for i = 1, 20 do save2.boxes[1][i] = { species = "PIDGEY" } end
  check(runToMenu(screen2), "reached the menu")
  local turn0 = battle2.turn
  screen2:useItem("MASTER_BALL")
  eq(battle2.outcome, nil, "the throw is refused")
  eq(save2.inventory.MASTER_BALL, 1, "the ball stays in the bag")
  eq(battle2.turn, turn0, "and the turn is not spent")
  check((screen2.message or ""):find("BOX"), "BallBoxFullText is what shows")
end

-- ---- SendMonIntoBox inserts at the HEAD, and reports a box it filled ------
do
  -- The species loop cascades every entry one slot down and ShiftBoxMon does
  -- the same for the OT names, nicknames and mon structs
  -- (engine/pokemon/move_mon.asm:954-968), so the catch is slot 1 -- which is
  -- what lets the FRIEND_BALL arm write sBoxMon1Happiness unconditionally
  -- ("The captured mon is now first in the box", item_effects.asm:624).
  local party = {}
  for i = 1, 6 do
    local mon = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
    mon.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    party[i] = mon
  end
  local screen, battle, _, wild, save =
    newScreen({ player = party[1], party = party,
      inventory = { MASTER_BALL = 1 } })
  local resident = { species = "PIDGEY" }
  save.boxes = { { resident } }
  check(runToMenu(screen), "reached the menu")
  screen:useItem("MASTER_BALL")
  eq(battle.outcome, "caught", "the Master Ball catch lands")
  eq(save.boxes[1][1], wild, "the catch is FIRST in the box")
  eq(save.boxes[1][2], resident, "and the mon already there shifted down one")
  eq(#save.boxes[1], 2, "with nothing lost off the end")
  eq(battle.boxFilled, nil, "a box with room left flags nothing")

  -- `.SendToPC` re-reads sBoxCount after the insert and sets
  -- BATTLERESULT_BOX_FULL when the catch is the one that filled it
  -- (item_effects.asm:612-619), which is what rings Bill on the first step
  -- back in the overworld.
  local party2 = {}
  for i = 1, 6 do
    local mon = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
    mon.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    party2[i] = mon
  end
  local screen2, battle2, _, _, save2 =
    newScreen({ player = party2[1], party = party2,
      inventory = { MASTER_BALL = 1 } })
  save2.boxes = { {} }
  for i = 1, 19 do save2.boxes[1][i] = { species = "PIDGEY" } end
  check(runToMenu(screen2), "reached the menu")
  screen2:useItem("MASTER_BALL")
  eq(battle2.outcome, "caught", "the twentieth catch still goes in")
  eq(#save2.boxes[1], 20, "and fills the box")
  eq(battle2.boxFilled, true, "which is flagged on the battle for the reload")
end

-- ---- a new species opens NewPokedexEntry, gated on CheckReceivedDex -------
do
  -- `predef NewPokedexEntry` sits between NewDexDataText and the party add
  -- (engine/items/item_effects.asm:535-542, :570).
  local function findEvent(screen, kind)
    for index, event in ipairs(screen.queue or {}) do
      if event.kind == kind then return index, event end
    end
  end

  local screen, _, _, _, save = newScreen({ inventory = { MASTER_BALL = 1 } })
  save.engineFlags = { [11] = true }
  save.pokedex = { seen = {}, caught = {} }
  check(runToMenu(screen), "reached the menu")
  screen:useItem("MASTER_BALL")
  local dexAt, dexEvent = findEvent(screen, "dex-entry")
  check(dexEvent ~= nil, "the catch queues a dex-entry event")
  eq(dexEvent and dexEvent.species, "PIDGEY", "on the species just caught")
  local nickAt = findEvent(screen, "ask-nickname")
  check(nickAt and dexAt and dexAt < nickAt,
    "and it runs ahead of AskGiveNicknameText")

  -- CheckReceivedDex: no dex, no line and no screen (item_effects.asm:532-533).
  local screen2, _, _, _, save2 = newScreen({ inventory = { MASTER_BALL = 1 } })
  save2.engineFlags = {}
  save2.pokedex = { seen = {}, caught = {} }
  check(runToMenu(screen2), "reached the menu")
  screen2:useItem("MASTER_BALL")
  eq(findEvent(screen2, "dex-entry"), nil, "a dexless player gets no entry")

  -- `jr nz, .skip_pokedex`: a row already owned skips both (:528-530).
  local screen3, _, _, _, save3 = newScreen({ inventory = { MASTER_BALL = 1 } })
  save3.engineFlags = { [11] = true }
  save3.pokedex = { seen = {}, caught = { PIDGEY = true } }
  check(runToMenu(screen3), "reached the menu")
  screen3:useItem("MASTER_BALL")
  eq(findEvent(screen3, "dex-entry"), nil, "an owned row opens nothing")
end

-- ---- the low-HP siren dies with the enemy, and with a healing item --------
do
  -- StopDangerSound plus the wBattleLowHealthAlarm latch on every wild enemy
  -- faint (engine/battle/core.asm:2071-2074), read first by CheckDanger
  -- (:4396-4399); and wLowHealthAlarm zeroed by the healing items before the
  -- HP even moves (engine/items/item_effects.asm:1657-1658).
  local siren = false
  local realStart, realStop = Sound.startLoop, Sound.stopLoop
  Sound.startLoop = function(_, name)
    if name == "Low_Health_Alarm" then siren = true end
  end
  Sound.stopLoop = function(name)
    if name == "Low_Health_Alarm" then siren = false end
  end

  local player = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local wild = Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local screen = newScreen({ player = player, wild = wild })
  check(runToMenu(screen), "reached the menu")
  player.hp = 2
  screen.shownHp.player = 2
  run(screen, 1)
  check(siren, "a red bar raises the siren")

  wild.hp = 1
  screen:submit({ kind = "move", move = "TACKLE" })
  -- The drain to zero still rings: AnimateHPBar runs before
  -- UpdateBattleStateAndExperienceAfterEnemyFaint is even reached.  What may
  -- not ring is anything from the faint onward.
  local latched, rangAfterFaint, sawExpLine = false, false, false
  for _ = 1, 3000 do
    drainStep(screen)
    if screen.lowHealthAlarmDisabled then latched = true end
    if latched and siren then rangAfterFaint = true end
    if latched and (screen.message or ""):find("EXP") then sawExpLine = true end
    if screen.phase == "done" then break end
  end
  eq(screen.phase, "done", "the win drains out")
  check(latched, "the enemy's faint latched wBattleLowHealthAlarm")
  check(sawExpLine, "and the exp lines ran after it with the bar still red")
  check(not rangAfterFaint,
    "and the siren is cut the instant the enemy goes down, not left blaring "
    .. "under the exp bar and the level-up lines")

  -- The item exception: silent from the frame it is used, all through the
  -- climb, with no latch behind it.
  local player2 = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  player2.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local screen2 = newScreen({ player = player2,
    inventory = { POTION = 1 } })
  check(runToMenu(screen2), "reached the menu")
  player2.hp = 2
  screen2.shownHp.player = 2
  run(screen2, 1)
  check(siren, "the second battle's siren is up too")
  screen2:useItem("POTION")
  screen2.game.stack.top().onChoose(1, player2)
  check(not siren, "the POTION silences it where UseDisposableItem sits")
  check(screen2.hpAnim and screen2.hpAnim.side == "player",
    "with the bar only starting to climb")
  local rangDuringClimb = false
  for _ = 1, 600 do
    Input:step()
    screen2:update(1 / 60)
    if screen2.hpAnim and siren then rangDuringClimb = true end
    if screen2.phase == "menu" then break end
  end
  check(not rangDuringClimb, "and it stays silent for the whole climb")

  Sound.startLoop, Sound.stopLoop = realStart, realStop
end

-- ---- the move list refuses a dry or disabled row --------------------------
--
-- `.no_pp_left` and `.move_disabled` both end on `jp MoveSelectionScreen`
-- (engine/battle/core.asm:5213-5246), so neither spends the turn.
local function tapper(screen)
  return function(button)
    Input:overlayPressed(button)
    Input:step()
    screen:update(1 / 60)
    Input:overlayReleased(button)
    Input:step()
    screen:update(1 / 60)
  end
end

do
  local lead = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  lead.moves = { { id = "GROWL", pp = 40, maxPp = 40 },
    { id = "TACKLE", pp = 5, maxPp = 35 } }
  local screen, _, _, wild = newScreen({ player = lead })
  check(runToMenu(screen), "reached the menu")
  screen.battle:volatile(screen.battle.player).disabled = "GROWL"
  local tap = tapper(screen)
  tap("a")
  eq(screen.phase, "moves", "A on FIGHT still opens the list")
  local before = wild.hp
  tap("a")
  eq(screen.phase, "refuse-move", "the disabled row is refused")
  eq(screen.message, "The move is DISABLED!", "with BattleText_TheMoveIsDisabled")
  eq(wild.hp, before, "and the enemy got no free turn")
  -- Both refusal lines end in `prompt` (data/text/battle.asm:315-323), so the
  -- list comes back on a press, not on a timer.
  tap("a")
  eq(screen.phase, "moves", "the list comes back")

  -- The same for a spent row.
  screen.battle:volatile(screen.battle.player).disabled = nil
  screen.battle.player.moves[2].pp = 0
  tap("down")
  eq(screen.moveIndex, 2, "onto the spent move")
  tap("a")
  eq(screen.phase, "refuse-move", "a 0 PP row is refused too")
  eq(screen.message, "There's no PP left for this move!",
     "with BattleText_TheresNoPPLeftForThisMove")
  eq(wild.hp, before, "and still no enemy turn")
  tap("a")
  eq(screen.phase, "moves", "and the list comes back again")
end

-- .CheckPlayerHasUsableMoves runs at MoveSelectionScreen's head
-- (engine/battle/core.asm:5058-5059): nothing usable never opens the list.
do
  local lead = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  lead.moves = { { id = "GROWL", pp = 40, maxPp = 40 },
    { id = "TACKLE", pp = 0, maxPp = 35 } }
  local screen = newScreen({ player = lead })
  check(runToMenu(screen), "reached the menu")
  screen.battle:volatile(screen.battle.player).disabled = "GROWL"
  local messages = {}
  local realPush = screen.pushAll
  screen.pushAll = function(self, events)
    for _, event in ipairs(events or {}) do
      if event.kind == "message" then messages[#messages + 1] = event.text end
    end
    return realPush(self, events)
  end
  tapper(screen)("a")
  check(screen.phase ~= "moves", "the list never opened")
  local struggled = false
  for _, text in ipairs(messages) do
    if text:find("has no moves left!", 1, true) then struggled = true end
  end
  check(struggled, "and the turn resolved as STRUGGLE")
end

-- ---- the move-learn prompts (engine/pokemon/learn.asm) -------------------
--
-- ForgetMove asks first (:123-127), the picker's B is LearnMove's .cancel
-- (:104-108) and a NO there is `jp c, .loop`, back to the ask.
local function learnScreen()
  local lead = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  lead.moves = { { id = "TACKLE", pp = 35, maxPp = 35 },
    { id = "GROWL", pp = 40, maxPp = 40 },
    { id = "THUNDER_WAVE", pp = 20, maxPp = 20 },
    { id = "SURF", pp = 15, maxPp = 15 } }
  local screen = newScreen({ player = lead, party = { lead } })
  check(runToMenu(screen), "reached the menu")
  screen:push({ kind = "choose-forget", index = 1,
    move = { id = "EMBER", pp = 25, maxPp = 25 }, moveName = "EMBER",
    text = "CYNDAQUIL wants to learn EMBER!" })
  screen:advanceQueue()
  return screen, lead
end

-- AskForgetMoveText's `para`/`cont` each want a press (home/text.asm:403-448),
-- so the question is reached by pages rather than by one button.
local function runToPhase(screen, phase, cap)
  for _ = 1, (cap or 900) do
    drainStep(screen)
    if screen.phase == phase then return true end
  end
  return false
end

do
  local screen, lead = learnScreen()
  eq(screen.phase, "learn-intro", "AskForgetMoveText's first page holds")
  eq(screen.message, "CYNDAQUIL is\ntrying to learn",
    "with _AskForgetMoveText's own wording (data/text/common_3.asm:141-165)")
  check(runToPhase(screen, "ask-forget"), "and its pages run into the question")
  eq(screen.message, "move to make room\nfor EMBER?",
    "whose last page is the one YesNoBox opens over")
  local tap = tapper(screen)
  -- The question's own `prompt` is read first and YesNoBox opens after it,
  -- exactly as OfferSwitch does (engine/battle/core.asm:3298-3305), so the
  -- answer is the second press, not the first.
  tap("a")
  eq(screen.phase, "ask-forget", "the last page holds until it is read")
  tap("b")
  eq(screen.phase, "stop-learning", "NO there asks whether to stop learning")
  tap("a")
  tap("b")
  eq(screen.phase, "learn-intro", "and NO to THAT reprints the ask")
  check(runToPhase(screen, "ask-forget"), "which is a loop, not an exit")
  eq(lead.moves[1].id, "TACKLE", "and the moveset is untouched throughout")
  eq(#lead.moves, 4, "with nothing added")
end

do
  local screen, lead = learnScreen()
  check(runToPhase(screen, "ask-forget"), "the pages reach the question")
  local tap = tapper(screen)
  tap("a")                      -- read the question
  tap("a")                      -- YES
  eq(screen.phase, "choose-forget", "YES opens the picker")
  tap("a")                      -- slot 1
  eq(lead.moves[1].id, "EMBER", "and A on slot 1 learns the move there")
end

-- IsHMMove refuses the slot and `jr .loop` redraws the list (learn.asm:193-197).
do
  local screen, lead = learnScreen()
  check(runToPhase(screen, "ask-forget"), "the pages reach the question")
  local tap = tapper(screen)
  tap("a")                      -- read the question
  tap("a")                      -- YES
  eq(screen.phase, "choose-forget", "the picker is up")
  screen.forgetIndex = 4
  tap("a")
  eq(screen.phase, "choose-forget", "A on the HM row keeps the list")
  eq(screen.message, "HM moves can't be\nforgotten now.",
    "with MoveCantForgetHMText")
  eq(screen.forgetIndex, 1, "and `jr .loop` puts the cursor back on slot 1")
  tap("a")
  eq(screen.phase, "choose-forget", "the picker is still up after the line")
  eq(lead.moves[4].id, "SURF", "and SURF is still there")
end

-- ---- GetMovePriority's Vital Throw carve-out (#1475) ----------------------
-- engine/battle/core.asm:787-789
do
  local screen = newScreen()
  check(runToMenu(screen), "reached the menu")
  local battle = screen.battle
  local moves = battle.data.moves
  moves.VITAL_THROW = { id = "VITAL_THROW", name = "VITALTHROW", power = 70,
    type = "NORMAL", accuracy = 100, pp = 10, effect = "EFFECT_ALWAYS_HIT" }
  moves.SWIFT = { id = "SWIFT", name = "SWIFT", power = 60, type = "NORMAL",
    accuracy = 100, pp = 20, effect = "EFFECT_ALWAYS_HIT" }
  moves.QUICK_ATTACK = { id = "QUICK_ATTACK", name = "QUICKATTACK", power = 40,
    type = "NORMAL", accuracy = 100, pp = 30, effect = "EFFECT_PRIORITY_HIT" }
  eq(battle:movePriority("VITAL_THROW"), -1, "VITAL_THROW goes last")
  eq(battle:movePriority("SWIFT"), 0,
    "while SWIFT, which shares its effect, keeps BASE_PRIORITY")
  eq(battle:movePriority("QUICK_ATTACK"), 1, "and the table still reads")
  moves.ROAR_FIX = { id = "ROAR_FIX", name = "ROAR", power = 0,
    type = "NORMAL", accuracy = 100, pp = 20, effect = "EFFECT_FORCE_SWITCH" }
  -- MoveEffectPriorities: EFFECT_FORCE_SWITCH is 0, below BASE_PRIORITY
  -- (data/moves/effects_priorities.asm:5)
  eq(battle:movePriority("ROAR_FIX"), -1,
    "Whirlwind and Roar sit below BASE_PRIORITY")
  eq(battle:orderOf("VITAL_THROW", "ROAR_FIX"), "player",
    "VITAL_THROW ties a force-switch move (0 vs 0), so Speed decides")
  eq(battle:orderOf("TACKLE", "TACKLE"), "player",
    "the faster mon leads on equal priority")
  eq(battle:orderOf("VITAL_THROW", "TACKLE"), "enemy",
    "but VITAL_THROW loses to a normal move whatever the Speed")
  moves.VITAL_THROW, moves.SWIFT, moves.QUICK_ATTACK = nil, nil, nil
  moves.ROAR_FIX = nil
end

-- ---- a send-out snapshots HP at send time (#1514) -------------------------
-- SendOutPlayerMon's tail (engine/battle/core.asm:3796-3838)
do
  local lead = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  local bench = Mon.new(DATA, "TOTODILE", 10, { dvs = perfect })
  local screen, battle = newScreen({ player = lead, party = { lead, bench } })
  check(runToMenu(screen), "reached the menu")
  battle:takeEvents()
  check(battle:switch(2), "the bench mon comes in")
  local send = battle:takeEvents()[1]
  eq(send.kind, "send", "the switch emits a send-out")
  eq(send.hp, bench.hp, "carrying a numeric HP snapshot")
  bench.hp = bench.hp - 7
  check(send.hp ~= bench.hp,
    "which the rest of the turn's damage cannot walk back")
  screen.shownHp.player = 0
  screen:push(send)
  screen:advanceQueue()
  eq(screen.shownHp.player, send.hp,
    "and the HUD opens on the snapshot, not on the post-hit value")
end

-- ---- the send-out snapshots level and exp the same way (#1514) ------------
-- SendOutPlayerMon reloads wBattleMon* from the party slot (core.asm:3796-3838)
do
  local lead = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  local bench = Mon.new(DATA, "TOTODILE", 10, { dvs = perfect })
  local screen, battle = newScreen({ player = lead, party = { lead, bench } })
  check(runToMenu(screen), "reached the menu")
  battle:takeEvents()
  check(battle:switch(2), "the bench mon comes in")
  local send = battle:takeEvents()[1]
  eq(send.level, bench.level, "the send carries a level snapshot")
  eq(send.experience, bench.experience, "and an experience snapshot")
  -- awardExperience mutates the live table before the UI dequeues the send
  bench.level = bench.level + 3
  bench.experience = (bench.experience or 0) + 5000
  screen:push(send)
  screen:advanceQueue()
  eq(screen.shownLevel, send.level,
    "the HUD opens on the send-time level, not the post-award one")
  eq(screen.shownExp, screen:expPixels(bench, send.level, send.experience),
    "and the exp bar fills from the send-time experience")
end

-- ---- LearnMove finishes before the queued send-out (#1516) ----------------
-- LearnMove inside GiveExperiencePoints (engine/battle/core.asm:1959-2010)
do
  local screen, lead = learnScreen()
  screen:push({ kind = "send", side = "enemy", mon = { hp = 1 }, hp = 1,
    text = "JOE sent out PIDGEY!" })
  check(runToPhase(screen, "ask-forget"), "the pages reach the question")
  local tap = tapper(screen)
  tap("a")                      -- read the question
  tap("a")                      -- YES
  eq(screen.phase, "choose-forget", "YES opens the picker")
  tap("a")                      -- slot 1
  eq(lead.moves[1].id, "EMBER", "the move is learned")
  check(screen.message and screen.message:find("forgot", 1, true) ~= nil,
    "and its line prints ahead of the send-out that was already queued")
end

-- ---- MoveSelectionScreen's two boxes (#1478) ------------------------------
-- engine/battle/core.asm:5074-5094, MoveInfoBox :5403-5478
do
  local Chrome = require("src.ui.gen2.Chrome")
  local lead = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  lead.moves = { { id = "TACKLE", pp = 30, maxPp = 35 },
    { id = "THUNDER_WAVE", pp = 20, maxPp = 20 } }
  local screen = newScreen({ player = lead, party = { lead } })
  check(runToMenu(screen), "reached the menu")
  screen.phase = "moves"
  screen.moveIndex = 1

  local boxes, prints = {}, {}
  local saved = { box = Chrome.box, print = Chrome.print,
    printRight = Chrome.printRight, cursor = Chrome.cursor }
  Chrome.box = function(x, y, w, h)
    boxes[#boxes + 1] = ("%d,%d,%d,%d"):format(x, y, w, h)
  end
  Chrome.print = function(text, x, y)
    prints[#prints + 1] = ("%s@%d,%d"):format(tostring(text), x, y)
  end
  Chrome.printRight = function(text, x, y)
    prints[#prints + 1] = ("R:%s@%d,%d"):format(tostring(text), x, y)
  end
  Chrome.cursor = function(x, y)
    prints[#prints + 1] = ("cursor@%d,%d"):format(x, y)
  end
  local ok, err = pcall(function() screen:drawPanel() end)
  Chrome.box, Chrome.print = saved.box, saved.print
  Chrome.printRight, Chrome.cursor = saved.printRight, saved.cursor
  check(ok, "the move menu draws: " .. tostring(err))

  local drawn = table.concat(boxes, " ")
  check(drawn:find("0,8,11,5", 1, true) ~= nil, "the TYPE/PP box is drawn")
  check(drawn:find("4,12,16,6", 1, true) ~= nil, "over the narrow list box")
  -- SafeLoadTempTilemapToTilemap keeps the full battle textbox under the
  -- move list (core.asm:4689); Textbox then MoveInfoBox over it (:5084, :5157).
  check(drawn:find("0,12,20,6", 1, true) ~= nil,
    "over the restored full-width message box")
  local base = drawn:find("0,12,20,6", 1, true)
  local list = drawn:find("4,12,16,6", 1, true)
  local info = drawn:find("0,8,11,5", 1, true)
  check(base < list and list < info,
    "painted base box, then list box, then info box")
  local text = table.concat(prints, " ")
  check(text:find("TACKLE@6,13", 1, true) ~= nil, "names sit at column 6")
  check(text:find("cursor@5,13", 1, true) ~= nil, "with the cursor at 5")
  check(text:find("TYPE/@1,9", 1, true) ~= nil, "TYPE/ at (1,9)")
  check(text:find("NORMAL@2,10", 1, true) ~= nil, "the type name at (2,10)")
  check(text:find("30/35@5,11", 1, true) ~= nil,
    "and only the highlighted move's PP, at (5,11)")
  check(text:match("R:%d+/%d+@19,1%d") == nil, "no PP is printed per row")
end

S.finish()
