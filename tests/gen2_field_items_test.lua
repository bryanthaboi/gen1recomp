-- Field item use from the Gen 2 PACK: pack.asm UseItem's .Party arm
-- (src/core/gen2/ItemEffects.lua + Game2:usePartyItem), the
-- ESCAPE ROPE / DIG / TELEPORT escape family (World:useEscapeRope,
-- FieldMoves.digFromMenu / teleportFromMenu over EscapeRopeOrDig,
-- engine/events/overworld.asm), the SQUIRTBOTTLE's queued tree script
-- (engine/events/squirtbottle.asm _Squirtbottle), and the .Oak refusal for
-- field-NOUSE items.  The cache-backed sections skip without a gold cache,
-- the same guard tests/gen2_pokecenter_stairs_test.lua uses.
package.path = "./?.lua;./?/init.lua;" .. package.path

-- The UI modules require love-side helpers at load time; stub what they
-- touch.  Nothing here draws.
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
love.filesystem = love.filesystem or {
  load = function() return nil end,
  getInfo = function() return nil end,
  read = function() return nil end,
  write = function() return true end,
  remove = function() return true end,
}
love.timer = love.timer or { getTime = function() return 0 end }

require("src.core.Logger").warn = function() end

local S = require("tests.harness").suite("gen2 field items")
local check, eq = S.check, S.eq

local Game2 = require("src.core.Game2")
local ItemEffects = require("src.core.gen2.ItemEffects")
local FieldMoves = require("src.world.gen2.FieldMoves")
local Mon = require("src.battle.gen2.Mon")
local PackMenu = require("src.ui.gen2.PackMenu")
local Strings = require("src.core.Strings")

-- ------------------------------------------------------------------ fixtures

local DATA = {
  audio = { sfx = {}, sfxOrder = {} },
  tokens = require("src.render.TextBox").TOKENS,
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
      -- EMBER at 12 makes a candy from 11 offer exactly one move.
      levelMoves = {
        { level = 1, move = "TACKLE" },
        { level = 12, move = "EMBER" },
      },
      tmhm = { "SWIFT" },
    },
  },
  moves = {
    TACKLE = { id = "TACKLE", name = "TACKLE", pp = 35 },
    EMBER = { id = "EMBER", name = "EMBER", pp = 25 },
    SURF = { id = "SURF", name = "SURF", pp = 15 },
    SMOKESCREEN = { id = "SMOKESCREEN", name = "SMOKESCREEN", pp = 20 },
    SWIFT = { id = "SWIFT", name = "SWIFT", pp = 20 },
  },
  items = {
    POTION = { id = "POTION", name = "POTION", pocket = "ITEM", index = 18,
      fieldMenu = "ITEMMENU_PARTY", battleMenu = "ITEMMENU_PARTY" },
    ETHER = { id = "ETHER", name = "ETHER", pocket = "ITEM", index = 69,
      fieldMenu = "ITEMMENU_PARTY", battleMenu = "ITEMMENU_PARTY" },
    X_ATTACK = { id = "X_ATTACK", name = "X ATTACK", pocket = "ITEM",
      index = 49, fieldMenu = "ITEMMENU_NOUSE", battleMenu = "ITEMMENU_CLOSE" },
    POKE_BALL = { id = "POKE_BALL", name = "POKE BALL", pocket = "BALL",
      index = 5, fieldMenu = "ITEMMENU_NOUSE", battleMenu = "ITEMMENU_CLOSE" },
    TM01 = { id = "TM01", name = "TM01", pocket = "TM_HM", index = 191,
      fieldMenu = "ITEMMENU_PARTY", battleMenu = "ITEMMENU_NOUSE",
      teaches = "SWIFT" },
    -- a mod's own field item, whose action lives only in gen2ItemEffects
    -- below -- ItemEffects.RECORDS (the module's built-in table) has never
    -- heard of it, so resolving it at all requires the merged dataset (#8)
    MOD_ITEM = { id = "MOD_ITEM", name = "MOD ITEM", pocket = "ITEM",
      index = 250, fieldMenu = "ITEMMENU_PARTY", battleMenu = "ITEMMENU_PARTY" },
  },
  gen2ItemEffects = {
    MOD_ITEM = {
      action = "heal", field = true, needsTarget = true,
      use = function(ctx)
        local mon = ctx.mon
        if mon.hp >= mon.maxHp then
          return { used = false, text = "It won't have\nany effect." }
        end
        mon.hp = math.min(mon.maxHp, mon.hp + 5)
        return { used = true, text = "MOD ITEM used!" }
      end,
    },
  },
  gen2MenuGfx = {},
  gen2Icons = {
    species = { CYNDAQUIL = "ICON_FOX" },
    icons = { ICON_FOX = { id = "ICON_FOX", image = "x/fox.png" } },
  },
}

local function newInput()
  local input = { pressed = {}, down = {} }
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

local function newStack()
  return {
    _items = {},
    push = function(self, s) self._items[#self._items + 1] = s end,
    pop = function(self) return table.remove(self._items) end,
    top = function(self) return self._items[#self._items] end,
    clear = function(self)
      while #self._items > 0 do self:pop() end
    end,
  }
end

local function fixtureMon(level, fields)
  local built = Mon.new(DATA, "CYNDAQUIL", level or 12, {
    dvs = { attack = 15, defense = 15, speed = 15, special = 15 },
    moves = {
      { id = "TACKLE", pp = 30, maxPp = 35 },
      { id = "SURF", pp = 15, maxPp = 15 },
    },
  })
  for key, value in pairs(fields or {}) do built[key] = value end
  return built
end

-- Drives whatever is on top of the stack (party menu, move list, text box)
-- with an A press per frame until `predicate` answers true.
local function drive(game, predicate, frames)
  for _ = 1, frames or 600 do
    if predicate() then return true end
    local top = game.stack:top()
    if not top then return predicate() end
    game.input:press("a")
    if top.update then top:update(1 / 60) end
  end
  return predicate()
end

-- --------------------------------------------- ItemEffects: HP restoration

do
  local mon = fixtureMon(12, { hp = 10 })
  local result = ItemEffects.useOnMon("POTION", mon, DATA)
  eq(result.used, true, "a POTION on a hurt mon is spent")
  eq(mon.hp, 30, "and heals HealingHPAmounts' 20")
  eq(result.text, "CYNDAQUIL\nrecovered 20HP!", "with the cart's line")

  local capped = fixtureMon(12, { hp = mon.maxHp - 5 })
  local capResult = ItemEffects.useOnMon("HYPER_POTION", capped, DATA)
  eq(capResult.used, true, "a heal near full HP still lands")
  eq(capped.hp, capped.maxHp, "capped at max HP")
  eq(capResult.text, "CYNDAQUIL\nrecovered 5HP!", "printing the real delta")

  local full = fixtureMon(12)
  eq(ItemEffects.useOnMon("POTION", full, DATA).used, false,
    "a full-HP target refuses (IsMonAtFullHealth)")
  local fainted = fixtureMon(12, { hp = 0 })
  local faintResult = ItemEffects.useOnMon("POTION", fainted, DATA)
  eq(faintResult.used, false, "a fainted target refuses (IsMonFainted)")
  eq(faintResult.text, ItemEffects.TEXT_NO_EFFECT,
    "with ItemWontHaveEffectText")
end

-- ------------------------------------------------ ItemEffects: status heals

do
  local psn = fixtureMon(12, { status = "psn" })
  local result = ItemEffects.useOnMon("ANTIDOTE", psn, DATA)
  eq(result.used, true, "ANTIDOTE cures poison")
  eq(psn.status, nil, "the status byte clears")
  eq(result.text, "CYNDAQUIL's\ncured of poison.", "with the party text")

  local brn = fixtureMon(12, { status = "brn" })
  eq(ItemEffects.useOnMon("ANTIDOTE", brn, DATA).used, false,
    "ANTIDOTE refuses a burn (the mask does not intersect)")
  eq(brn.status, "brn", "and leaves it standing")

  local slp = fixtureMon(12, { status = "sleep" })
  local healAll = ItemEffects.useOnMon("FULL_HEAL", slp, DATA)
  eq(healAll.used, true, "FULL_HEAL's $ff mask takes any status")
  eq(healAll.text, "CYNDAQUIL's\nhealth returned.", "as HEAL_ALL")

  local clean = fixtureMon(12)
  eq(ItemEffects.useOnMon("FULL_HEAL", clean, DATA).used, false,
    "a clean mon refuses a status heal")

  -- FullRestoreEffect: full HP falls through to FullyHealStatus.
  local par = fixtureMon(12, { status = "par" })
  local restore = ItemEffects.useOnMon("FULL_RESTORE", par, DATA)
  eq(restore.used, true, "FULL RESTORE at full HP still cures the status")
  eq(par.status, nil, "clearing it")
  local hurt = fixtureMon(12, { hp = 3, status = "psn" })
  local both = ItemEffects.useOnMon("FULL_RESTORE", hurt, DATA)
  eq(both.used, true, "FULL RESTORE below full HP heals")
  eq(hurt.hp, hurt.maxHp, "to full")
  eq(hurt.status, nil, "and clears the status alongside (.FullRestore)")
end

-- ---------------------------------------------------- ItemEffects: revives

do
  local down = fixtureMon(12, { hp = 0, status = "psn" })
  local result = ItemEffects.useOnMon("REVIVE", down, DATA)
  eq(result.used, true, "REVIVE stands a fainted mon up")
  eq(down.hp, math.floor(down.maxHp / 2), "at half max HP (ReviveHalfHP)")
  eq(down.status, nil, "with the status wiped")
  eq(result.text, "CYNDAQUIL\nis revitalized.", "and the cart's line")

  local down2 = fixtureMon(12, { hp = 0 })
  ItemEffects.useOnMon("MAX_REVIVE", down2, DATA)
  eq(down2.hp, down2.maxHp, "MAX REVIVE restores full HP")

  local up = fixtureMon(12)
  eq(ItemEffects.useOnMon("REVIVE", up, DATA).used, false,
    "a standing mon refuses a REVIVE")

  local egg = fixtureMon(12, { isEgg = true, hp = 0 })
  local eggResult = ItemEffects.useOnMon("REVIVE", egg, DATA)
  eq(eggResult.used, false, "an EGG refuses (UseItem_SelectMon's cp EGG)")
  eq(eggResult.text, ItemEffects.TEXT_CANT_USE_ON_EGG, "with the EGG line")
end

-- ------------------------------------------------- ItemEffects: RARE CANDY

do
  local mon = fixtureMon(11, { hp = 20 })
  local before = { max = mon.maxHp, exp = mon.experience }
  local result = ItemEffects.useOnMon("RARE_CANDY", mon, DATA)
  eq(result.used, true, "a RARE CANDY below MAX_LEVEL is spent")
  eq(mon.level, 12, "one level up")
  eq(mon.experience, Mon.experienceForLevel(
    DATA.pokemon.growthRates.GROWTH_MEDIUM_SLOW, 12),
    "experience SET to CalcExpAtLevel's threshold")
  check(mon.maxHp > before.max, "stats recomputed at the new level")
  eq(mon.hp, 20 + (mon.maxHp - before.max),
    "current HP gains exactly the max-HP delta")
  eq(result.text, "CYNDAQUIL grew to\nlevel 12!", "with the grew-to line")
  eq(#result.learned, 1, "LearnLevelMoves offers the level-12 move")
  eq(result.learned[1], "EMBER", "which is EMBER")

  local capped = fixtureMon(11, { level = Mon.MAX_LEVEL })
  eq(ItemEffects.useOnMon("RARE_CANDY", capped, DATA).used, false,
    "MAX_LEVEL refuses (cp MAX_LEVEL / jp nc, NoEffectMessage)")
end

-- ------------------------------------------------- ItemEffects: partyAction

do
  for _, itemId in ipairs({ "HP_UP", "PROTEIN", "IRON", "CARBOS", "CALCIUM",
                            "PP_UP" }) do
    check(ItemEffects.partyAction(itemId, DATA) ~= nil,
      itemId .. " resolves a party action (#1249)")
  end
  eq(ItemEffects.partyAction("ZINC", DATA), nil,
    "ZINC does not exist in Gen 1 or Gen 2")
end

-- ------------------------------------------------- ItemEffects: VITAMIN

do
  local mon = fixtureMon(12)
  local before = { hp = mon.hp, maxHp = mon.maxHp }
  local result = ItemEffects.useOnMon("HP_UP", mon, DATA)
  eq(result.used, true, "an HP UP under the ceiling is spent")
  eq(mon.statExp.hp, 2560, "StatExpItemPointerOffsets' +10 high-byte add")
  check(mon.maxHp > before.maxHp, "UpdateStatsAfterItem recomputes max HP")
  eq(mon.stats.hp, mon.maxHp, "the recomputed hp stat lands on stats too")
  eq(mon.hp, before.hp, "current HP is UNCHANGED by HP UP")
  eq(result.text, "CYNDAQUIL's\nHEALTH rose.", "with the cart's stat line")

  local ceiling = fixtureMon(12, { statExp = {
    hp = 25600, attack = 0, defense = 0, speed = 0, special = 0 } })
  local refused = ItemEffects.useOnMon("HP_UP", ceiling, DATA)
  eq(refused.used, false, "25600 stat exp refuses (cp 100 / jr nc)")
  eq(ceiling.statExp.hp, 25600, "and leaves the word untouched")
  eq(refused.text, ItemEffects.TEXT_NO_EFFECT, "with NoEffectMessage")

  local edge = fixtureMon(12, { statExp = {
    hp = 25599, attack = 0, defense = 0, speed = 0, special = 0 } })
  local accepted = ItemEffects.useOnMon("HP_UP", edge, DATA)
  eq(accepted.used, true, "25599 is still under the ceiling")
  eq(edge.statExp.hp, 28159, "landing on 25599 + 2560")

  local labels = {
    HP_UP = { stat = "hp", label = "HEALTH" },
    PROTEIN = { stat = "attack", label = "ATTACK" },
    IRON = { stat = "defense", label = "DEFENSE" },
    CARBOS = { stat = "speed", label = "SPEED" },
    CALCIUM = { stat = "special", label = "SPECIAL" },
  }
  for itemId, row in pairs(labels) do
    local target = fixtureMon(12)
    local outcome = ItemEffects.useOnMon(itemId, target, DATA)
    eq(target.statExp[row.stat], 2560, itemId .. " raises its own stat exp")
    eq(outcome.text, ("CYNDAQUIL's\n%s rose."):format(row.label),
      itemId .. " prints " .. row.label)
  end
end

-- ------------------------------------------------- ItemEffects: PP family

do
  local mon = fixtureMon(12)
  eq(ItemEffects.usePpItem("ETHER", mon, 1).used, true,
    "an ETHER on a drained slot is spent")
  eq(mon.moves[1].pp, 35, "restoring 10 capped at max (30 + 10 > 35)")
  eq(ItemEffects.usePpItem("ETHER", mon, 2).used, false,
    "a slot already at max refuses (.dont_restore)")

  local berry = fixtureMon(12)
  berry.moves[1].pp = 10
  ItemEffects.usePpItem("MYSTERYBERRY", berry, 1)
  eq(berry.moves[1].pp, 15, "MYSTERYBERRY restores 5")

  local deep = fixtureMon(12)
  deep.moves[1].pp = 0
  ItemEffects.usePpItem("MAX_ETHER", deep, 1)
  eq(deep.moves[1].pp, 35, "MAX ETHER restores the whole slot")

  local elixer = fixtureMon(12)
  elixer.moves[1].pp = 5
  elixer.moves[2].pp = 3
  local all = ItemEffects.usePpItem("ELIXER", elixer)
  eq(all.used, true, "an ELIXER needs no slot")
  eq(elixer.moves[1].pp, 15, "restoring 10 to every move")
  eq(elixer.moves[2].pp, 13, "each capped by its own max")
  eq(all.text, ItemEffects.TEXT_PP_RESTORED, "with PPRestoredText")

  local fullMon = fixtureMon(12)
  fullMon.moves[1].pp = 35
  eq(ItemEffects.usePpItem("MAX_ELIXER", fullMon).used, false,
    "a party mon with every slot full refuses the ELIXER family")
end

-- ------------------------------------------------- ItemEffects: PP UP

do
  local mon = fixtureMon(12)
  for use = 1, 3 do
    local result = ItemEffects.usePpItem("PP_UP", mon, 1, DATA)
    eq(result.used, true, "PP UP use " .. use .. " of 3 is spent")
    eq(mon.moves[1].ppUps, use, "PP_UP_ONE ticks the top two bits")
    eq(mon.moves[1].maxPp, 35 + use * 7,
      "min(floor(basePP / 5), 7) added per use")
    eq(mon.moves[1].pp, 30 + use * 7, "current PP rises by the same amount")
  end
  local capped = ItemEffects.usePpItem("PP_UP", mon, 1, DATA)
  eq(capped.used, false, "a 4th PP UP refuses (PP_UP_MASK's 3-use cap)")
  eq(mon.moves[1].maxPp, 56, "and leaves max PP where it was")
  eq(capped.text, "TACKLE's PP\nis maxed out.", "with PPIsMaxedOutText")

  local sketch = fixtureMon(12)
  sketch.moves[1] = { id = "SKETCH", pp = 1, maxPp = 1 }
  local sketchResult = ItemEffects.usePpItem("PP_UP", sketch, 1, DATA)
  eq(sketchResult.used, false, "SKETCH refuses a PP UP")
  eq(sketchResult.text, "SKETCH's PP\nis maxed out.",
    "with the same maxed-out line")

  local modMon = fixtureMon(12)
  modMon.moves[1] = { id = "MOD_MOVE", pp = 5 }
  local unknown = ItemEffects.usePpItem("PP_UP", modMon, 1, DATA)
  eq(unknown.used, false,
    "an id absent from data.moves with no maxPp refuses (base PP unknown)")
  eq(modMon.moves[1].ppUps, nil, "and is not consumed")
  eq(modMon.moves[1].pp, 5, "with current PP untouched")
  eq(unknown.text, "MOD_MOVE's PP\nis maxed out.",
    "printing the same maxed-out line rather than PP 0")
end

-- ------------------------------------------------ Game2: the .Party wiring
-- The REAL flow: usePartyItem pushes the real Gen2PartyMenu, the pick runs
-- the effect, the consumption happens, and the message rides a real TextBox
-- whose dismissal leaves the state UNDER it alone (the say() teardown
-- contract).

local function newHost(inventory, party)
  local host = setmetatable({
    data = DATA,
    save = {
      player = { name = "GOLD" },
      party = party or { fixtureMon(12, { hp = 10 }) },
      inventory = inventory or {},
      options = {},
    },
    options = {},
    input = newInput(),
    stack = newStack(),
  }, { __index = Game2 })
  return host
end

do
  local host = newHost({ POTION = 2 })
  local packSentinel = { isPack = true }
  host.stack:push(packSentinel)
  host:useFieldItem("POTION")
  local party = host.stack:top()
  check(party ~= nil and party.prompt ~= nil, "USE pushes the party list")
  eq(party.prompt, "Use on which <PK><MN>?",
    "under UseOnWhichPKMNString")
  -- Pick the first mon: the real PartyMenu update loop takes the A press.
  drive(host, function() return party.itemResult ~= nil end)
  -- engine/items/item_effects.asm:1748
  check(party.itemResult ~= nil, "the pick stays in the party list")
  eq(party.itemResult.text, "CYNDAQUIL\nrecovered 20HP!",
    "with PARTYMENUTEXT_HEAL_HP in the list's box")
  eq(party.itemResult.shown, 10, "the bar starts at the pre-heal HP")
  eq(party.itemResult.target, 30, "and climbs to the healed value")
  eq(host.save.party[1].hp, 30, "the POTION healed through the real menu")
  eq(host.save.inventory.POTION, 1, "and one POTION left the pack")
  drive(host, function() return host.stack:top() == packSentinel end)
  eq(host.stack:top(), packSentinel,
    "the button returns to the pack, not past it")
end

do
  -- The refusal path spends nothing.
  local host = newHost({ POTION = 2 }, { fixtureMon(12) })
  host:useFieldItem("POTION")
  local party = host.stack:top()
  drive(host, function() return host.stack:top() ~= party end)
  eq(host.save.inventory.POTION, 2, "a refused heal costs nothing")
  local box = host.stack:top()
  check(box ~= nil and box.pages ~= nil, "and prints the no-effect line")
end

do
  local mon = fixtureMon(12)
  local host = newHost({ HP_UP = 1 }, { mon })
  host:useFieldItem("HP_UP")
  local party = host.stack:top()
  check(party ~= nil and party.prompt ~= nil,
    "USE pushes the party list (partyAction is no longer nil)")
  drive(host, function() return host.stack:top() ~= party end)
  eq(mon.statExp.hp, 2560, "the vitamin ran through the real menu")
  eq(host.save.inventory.HP_UP, nil, "and the HP UP was spent")
end

do
  -- #8 regression: Game2:usePartyItem asked ItemEffects.partyAction for the
  -- item's family with no `data` argument, so it could only ever see
  -- RECORDS -- the module's own built-ins.  A mod's field item, whose
  -- action exists only in the merged gen2ItemEffects table, resolved to a
  -- nil action and fell straight through to the "isn't going to help here"
  -- refusal instead of opening the party list at all.
  local mon = fixtureMon(12, { hp = 10 })
  local host = newHost({ MOD_ITEM = 1 }, { mon })
  host:useFieldItem("MOD_ITEM")
  local party = host.stack:top()
  check(party ~= nil and party.prompt ~= nil,
    "a mod's own gen2ItemEffects record opens the party list")
  drive(host, function() return host.stack:top() ~= party end)
  eq(mon.hp, 15, "the mod item's own use() ran through the real menu")
  eq(host.save.inventory.MOD_ITEM, nil, "and the mod item was spent")
end

do
  local mon = fixtureMon(12, { statExp = {
    hp = 25600, attack = 0, defense = 0, speed = 0, special = 0 } })
  local host = newHost({ HP_UP = 2 }, { mon })
  host:useFieldItem("HP_UP")
  local party = host.stack:top()
  drive(host, function() return host.stack:top() ~= party end)
  eq(host.save.inventory.HP_UP, 2, "a refused HP UP costs nothing")
  eq(mon.statExp.hp, 25600, "and leaves the stat exp word untouched")
end

do
  -- ETHER: party pick, then the move list, then the restore.
  local mon = fixtureMon(12)
  local host = newHost({ ETHER = 1 }, { mon })
  host:useFieldItem("ETHER")
  local party = host.stack:top()
  check(party ~= nil, "ETHER opens the party list")
  drive(host, function() return host.stack:top() ~= party end)
  local mover = host.stack:top()
  check(mover ~= nil and mover.list ~= nil,
    "the pick opens the move list (Gen2MoveDeleter's shared screen)")
  drive(host, function() return host.stack:top() ~= mover end)
  eq(mon.moves[1].pp, 35, "slot one restored through the real screens")
  eq(host.save.inventory.ETHER, nil, "and the ETHER was spent")
end

do
  -- RARE CANDY: level line, then the learnset prompt for the level-12 move.
  local mon = fixtureMon(11, { hp = 20 })
  mon.moves = { { id = "TACKLE", pp = 30, maxPp = 35 } }
  local host = newHost({ RARE_CANDY = 1 }, { mon })
  host:useFieldItem("RARE_CANDY")
  local party = host.stack:top()
  drive(host, function() return host.stack:top() ~= party end)
  eq(mon.level, 12, "the candy leveled through the real party menu")
  drive(host, function() return host.stack:top() == nil end, 2000)
  eq(#mon.moves, 2, "the level-12 move was learned on the way out")
  eq(mon.moves[2].id, "EMBER", "and it is EMBER")
  eq(host.save.inventory.RARE_CANDY, nil, "with the candy spent")
end

-- ------------------------------------------------ TeachTMHM's LearnMove loop
-- engine/items/tmhm.asm TeachTMHM -> predef LearnMove (engine/pokemon/learn.asm):
-- a full moveset runs ForgetMove's ask / pick / "Stop learning" loop, and only
-- b = 1 pays HAPPINESS_LEARNMOVE and ConsumeTM.

local function fourMoveMon()
  local mon = fixtureMon(12)
  mon.moves = {
    { id = "TACKLE", pp = 30, maxPp = 35 },
    { id = "SURF", pp = 15, maxPp = 15 },
    { id = "SMOKESCREEN", pp = 20, maxPp = 20 },
    { id = "EMBER", pp = 25, maxPp = 25 },
  }
  return mon
end

-- One frame on whatever is on top, with the button this case answers with.
local function step(game, button)
  local top = game.stack:top()
  if not top then return nil end
  game.input:press(button)
  if top.update then top:update(1 / 60) end
  return top
end

local function firstLine(state)
  return state and state.pages and state.pages[1] and state.pages[1][1]
end

do
  -- YES, then slot one: the TM lands and is spent.
  local mon = fourMoveMon()
  local host = newHost({ TM01 = 1 }, { mon })
  local packSentinel = { isPack = true }
  host.stack:push(packSentinel)
  host:useFieldItem("TM01")
  local party = host.stack:top()
  check(party ~= nil and party.prompt ~= nil, "a TM opens the party list")
  drive(host, function() return host.stack:top() ~= party end)
  check(firstLine(host.stack:top()) == "CYNDAQUIL is",
    "a full moveset asks which move to forget, not a refusal")
  drive(host, function() return host.stack:top() == packSentinel end, 3000)
  eq(host.stack:top(), packSentinel, "the flow returns to the pack")
  eq(mon.moves[1].id, "SWIFT", "the picked slot took the TM's move")
  eq(#mon.moves, 4, "and the set is still four long")
  eq(host.save.inventory.TM01, nil, "with the TM consumed (ConsumeTM)")
end

do
  -- NO, then NO to "Stop learning": `jp c, .loop` reopens the question.
  local mon = fourMoveMon()
  local host = newHost({ TM01 = 1 }, { mon })
  host:useFieldItem("TM01")
  local party = host.stack:top()
  drive(host, function() return host.stack:top() ~= party end)
  local asks, seen = 0, {}
  for _ = 1, 900 do
    local top = host.stack:top()
    if not top or asks >= 2 then break end
    if not seen[top] and firstLine(top) == "CYNDAQUIL is" then
      seen[top] = true
      asks = asks + 1
    end
    step(host, "b")
  end
  eq(asks, 2, "refusing to stop learning reopens the delete question")
  eq(mon.moves[1].id, "TACKLE", "with the moveset untouched")
  eq(host.save.inventory.TM01, 1, "and the TM still in the pack")
end

do
  -- NO, then YES to "Stop learning": DidNotLearnMoveText, b = 0, nothing spent.
  local mon = fourMoveMon()
  local host = newHost({ TM01 = 1 }, { mon })
  host:useFieldItem("TM01")
  local party = host.stack:top()
  drive(host, function() return host.stack:top() ~= party end)
  local button = "b"
  for _ = 1, 900 do
    local top = host.stack:top()
    if not top then break end
    if firstLine(top) == "Stop learning" then button = "a" end
    step(host, button)
  end
  eq(host.stack:top(), nil, "giving up closes the whole LearnMove flow")
  eq(mon.moves[1].id, "TACKLE", "the moveset is untouched")
  eq(#mon.moves, 4, "still four moves")
  eq(host.save.inventory.TM01, 1, "and a refusal spends nothing")
end

do
  -- RARE CANDY into a full moveset: RareCandyEffect ends in LearnLevelMoves
  -- (engine/items/item_effects.asm) whose .learn arm is `predef LearnMove`
  -- (engine/pokemon/evolve.asm), so the level-12 move opens ForgetMove's ask.
  local mon = fixtureMon(11, { hp = 20 })
  mon.moves = {
    { id = "TACKLE", pp = 30, maxPp = 35 },
    { id = "SURF", pp = 15, maxPp = 15 },
    { id = "SMOKESCREEN", pp = 20, maxPp = 20 },
    { id = "SWIFT", pp = 20, maxPp = 20 },
  }
  local host = newHost({ RARE_CANDY = 1 }, { mon })
  host:useFieldItem("RARE_CANDY")
  local party = host.stack:top()
  drive(host, function() return host.stack:top() ~= party end)
  local asked = false
  for _ = 1, 900 do
    local top = host.stack:top()
    if not top then break end
    if firstLine(top) == "CYNDAQUIL is" then
      asked = true
      break
    end
    step(host, "a")
  end
  check(asked, "a candy's level-up move asks which move to forget")
  eq(mon.level, 12, "with the level already banked")
  -- YES, then slot one.
  drive(host, function() return host.stack:top() == nil end, 2000)
  eq(mon.moves[1].id, "EMBER", "the picked slot took the level-up move")
  eq(#mon.moves, 4, "and the set is still four long")
  eq(host.save.inventory.RARE_CANDY, nil, "with the candy spent")
end

-- --------------------------------------------- PackMenu: the .Oak refusal

do
  local fieldWorld = { useFieldItem = function() return nil end }
  local game = { input = newInput(), save = {
    player = { name = "GOLD" },
    inventory = { X_ATTACK = 1 },
    options = {},
  }, data = DATA, stack = newStack() }
  local chosen
  local pack = PackMenu.new(game, {
    save = game.save, items = DATA.items, world = fieldWorld,
    onChoose = function(id) chosen = id end,
  })
  pack:useSelected()
  check(pack.message ~= nil, "a field-NOUSE item prints in the pack")
  eq(pack.message[1], "OAK: {PLAYER}!", "OakThisIsntTheTimeText")
  eq(chosen, nil, "and never reaches onChoose")

  -- The DUDE's tutorial pack has a stub world and must still hand its
  -- field-NOUSE POKE BALL to the throw.
  local dudeGame = { input = newInput(), save = {
    player = { name = "GOLD" },
    inventory = { POKE_BALL = 1 },
    options = {},
  }, data = DATA, stack = newStack() }
  local thrown
  local dudePack = PackMenu.new(dudeGame, {
    save = dudeGame.save, items = DATA.items, world = {}, pocket = "BALL",
    onChoose = function(id) thrown = id end,
  })
  dudePack:useSelected()
  eq(thrown, "POKE_BALL", "the tutorial pack still throws")
  eq(dudePack.message, nil, "with no Oak line in the way")

  -- DepositSellPack passes the same empty world (the mart's SELL and the
  -- item PC's DEPOSIT both do): a TM row must hand its id back rather than
  -- open the teach party, which is issue #1243's "Teach which PKMN?" in
  -- the middle of a sale.
  local sellGame = { input = newInput(), save = {
    player = { name = "GOLD" },
    inventory = { TM01 = 1 },
    options = {},
  }, data = DATA, stack = newStack() }
  local sold
  local sellPack = PackMenu.new(sellGame, {
    save = sellGame.save, items = DATA.items, world = {},
    onChoose = function(id) sold = id end,
  })
  sellPack.pocketIndex = 4 -- TM_HM
  sellPack:rebuild()
  sellPack:useSelected()
  eq(sold, "TM01", "a chooser pack hands a TM to its caller")
  eq(sellPack.message, nil, "with no teach refusal in the way")
  eq(#sellGame.stack._items, 0, "and nothing pushed over the pack")
end

-- ------------------------------------------------ say(): the teardown rule

do
  local host = newHost({})
  local under = { name = "under" }
  host.stack:push(under)
  host:say(Strings(
    "An item in your\nPACK may be\fregistered for use\non SELECT Button."))
  local box = host.stack:top()
  check(box ~= under, "say() pushes the box")
  eq(#box.pages, 2, "MayRegisterItemText is two pages")
  eq(box.pages[1][1], "An item in your", "page one, line one")
  eq(box.pages[1][2], "PACK may be", "page one ends mid-sentence, as cart")
  drive(host, function() return host.stack:top() == under end, 3000)
  eq(host.stack:top(), under,
    "dismissing pops the box alone: the state under it survives")
  eq(#host.stack._items, 1, "and exactly one state remains")
end

-- ------------------------------------------------- FieldMoves: DIG / TELEPORT

do
  local dig = FieldMoves.digFromMenu({
    environment = "CAVE", canEscapeRope = true,
  })
  eq(dig.ok, true, "DIG works in a CAVE with a banked triple")
  eq(dig.action, "dig", "queuing the dig action")
  eq(FieldMoves.digFromMenu({
    environment = "ROUTE", canEscapeRope = true,
  }).ok, false, "DIG refuses outdoors (.CheckCanDig)")
  eq(FieldMoves.digFromMenu({
    environment = "CAVE", canEscapeRope = false,
  }).ok, false, "and with a dead triple (.fail)")

  eq(FieldMoves.teleportFromMenu({ environment = "TOWN" }).ok, true,
    "TELEPORT works in a TOWN")
  eq(FieldMoves.teleportFromMenu({ environment = "ROUTE" }).ok, true,
    "and on a ROUTE (CheckOutdoorMap)")
  eq(FieldMoves.teleportFromMenu({ environment = "CAVE" }).ok, false,
    "and refuses underground")
  eq(FieldMoves.FROM_MENU.DIG, FieldMoves.digFromMenu,
    "DIG is wired into the submenu table")
  eq(FieldMoves.FROM_MENU.TELEPORT, FieldMoves.teleportFromMenu,
    "and so is TELEPORT")
end

-- -------------------------------------------- cache-backed World sections

local cache = os.getenv("GOLD_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
end
local probe = io.open(cache .. "/data/generated/maps.lua", "r")
if not probe then
  check(true, "gold cache absent (SKIP)")
  S.finish()
  return
end
probe:close()

local function loadLua(rel) return assert(loadfile(cache .. "/" .. rel))() end
local maps = loadLua("data/generated/maps.lua")
local tilesets = loadLua("data/generated/tilesets.lua")
local scripts = loadLua("data/generated/scripts.lua")

local World = require("src.world.gen2.World")
local Map = require("src.world.gen2.Map")

-- A world over the real defs, the tests/gen2_pokecenter_stairs_test.lua way:
-- setMap records instead of baking an image; everything else is shipped code.
local function world(mapId, x, y, save)
  local game = {
    data = { audio = { sfxOrder = {} }, tokens = DATA.tokens,
      items = { ESCAPE_ROPE = { id = "ESCAPE_ROPE", index = 19 } } },
    save = save or { player = { name = "GOLD" }, options = {} },
    input = newInput(),
    stack = newStack(),
  }
  local w = World.new(game)
  w.maps, w.tilesets, w.scripts = maps, tilesets, scripts
  w.map = Map.new(maps[mapId], tilesets[maps[mapId].tileset])
  w.player = { cellX = x, cellY = y, facing = "down", moving = false }
  w.loaded = nil
  w.setMap = function(self, id, cx, cy, facing)
    self.loaded = { id = id, x = cx, y = cy, facing = facing }
    return true
  end
  return w, game
end

-- ../pokecrystal/engine/events/overworld.asm:851-872
local function pump(w)
  for _ = 1, 256 do
    if not (w.mapSetup or w.moveState) then return end
    if w.mapSetup then w:updateMapSetup() else w:updateMovement() end
  end
end

-- ESCAPE ROPE in a CAVE with the banked triple: consumed, queued, and the
-- queued action warps to the banked warp's own tile.
do
  local save = { player = { name = "GOLD" }, options = {},
    inventory = { ESCAPE_ROPE = 2 } }
  local w, game = world("UNION_CAVE_B2F", 5, 3, save)
  w.backupWarp = { map = "CHERRYGROVE_POKECENTER_1F", warp = 3 }
  local outcome = w:useEscapeRope("ESCAPE_ROPE")
  eq(outcome, "escape_rope", "the rope succeeds in a CAVE")
  eq(save.inventory.ESCAPE_ROPE, 1,
    "UseDisposableItem takes one on success only")
  check(w.queuedFieldMove ~= nil, "the script is QUEUED, not run in the pack")
  check(w:runQueuedFieldMove(), "and the drain runs it")
  local box = game.stack:top()
  check(box ~= nil and box.pages ~= nil, "the used-rope line is up")
  eq(box.pages[1][1], "GOLD used an", "addressed to the player")
  drive(game, function() return game.stack:top() == nil end, 3000)
  pump(w)
  eq(w.loaded and w.loaded.id, "CHERRYGROVE_POKECENTER_1F",
    "the warp pays out to the banked map")
  local dest = maps.CHERRYGROVE_POKECENTER_1F.warps[3]
  eq(w.loaded.x, dest.x, "on the banked warp's own x")
  eq(w.loaded.y, dest.y, "and y")
  eq(w.playerState, FieldMoves.PLAYER_NORMAL,
    "with VAR_MOVEMENT back to PLAYER_NORMAL")
end

-- The refusals: outdoors (TIN_TOWER_ROOF is environment ROUTE), and a CAVE
-- whose triple is dead.  Neither takes the item.
do
  local save = { player = { name = "GOLD" }, options = {},
    inventory = { ESCAPE_ROPE = 1 } }
  local w = world("TIN_TOWER_ROOF", 9, 5, save)
  eq(w:useEscapeRope("ESCAPE_ROPE"), "nowhere",
    "TIN TOWER ROOF refuses: its environment is ROUTE")
  eq(save.inventory.ESCAPE_ROPE, 1, "at no cost")

  local w2 = world("UNION_CAVE_B2F", 5, 3, save)
  w2.backupWarp = nil
  eq(w2:useEscapeRope("ESCAPE_ROPE"), "nowhere",
    "a CAVE with no banked triple refuses (.fail on the zeroed triple)")
  eq(save.inventory.ESCAPE_ROPE, 1, "still at no cost")

  local w3 = world("WHIRL_ISLAND_LUGIA_CHAMBER", 5, 3, save)
  w3.backupWarp = { map = "CHERRYGROVE_POKECENTER_1F", warp = 3 }
  eq(w3:useEscapeRope("ESCAPE_ROPE"), "escape_rope",
    "the Lugia chamber (environment CAVE) accepts")
end

-- DIG from the party submenu shares the whole path through the REAL
-- fieldContext.
do
  local save = { player = { name = "GOLD" }, options = {} }
  local w = world("UNION_CAVE_B2F", 5, 3, save)
  w.backupWarp = { map = "CHERRYGROVE_POKECENTER_1F", warp = 3 }
  local result = w:useFieldMove("DIG", { nickname = "SANDSHREW" })
  eq(result and result.ok, true, "DIG succeeds where the rope does")
  check(w.queuedFieldMove ~= nil, "and queues the same escape action")
  eq(w.queuedFieldMove.action, "dig", "as dig")

  local w2 = world("TIN_TOWER_ROOF", 9, 5, save)
  local refused = w2:useFieldMove("DIG", { nickname = "SANDSHREW" })
  eq(refused and refused.ok, false, "and refuses outdoors")
end

-- TELEPORT queues the whiteout-spawn return from an outdoor map.
do
  local save = { player = { name = "GOLD" }, options = {} }
  local w = world("ROUTE_36", 10, 10, save)
  local result = w:useFieldMove("TELEPORT", { nickname = "ABRA" })
  eq(result and result.ok, true, "TELEPORT works on a ROUTE")
  eq(w.queuedFieldMove.action, "teleport", "queuing the teleport action")
  local w2 = world("UNION_CAVE_B2F", 5, 3, save)
  local refused = w2:useFieldMove("TELEPORT", { nickname = "ABRA" })
  eq(refused and refused.ok, false, "and refuses in a cave")
end

-- SQUIRTBOTTLE: facing the Route 36 Sudowoodo, the queued script IS the
-- extracted WateredWeirdTreeScript slice -- battle and all; anywhere else
-- the queued script is the "nothing happened" line.
do
  local save = { player = { name = "GOLD" }, options = {},
    inventory = { SQUIRTBOTTLE = 1 } }
  -- The tree is object index 3 of the extracted ROUTE_36: movement 23
  -- (SPRITEMOVEDATA_SUDOWOODO) at (35, 9).
  local treeDef
  for _, obj in ipairs(maps.ROUTE_36.objects or {}) do
    if obj.movement == 23 then treeDef = obj end
  end
  check(treeDef ~= nil, "the extracted ROUTE_36 carries the Sudowoodo object")
  eq(treeDef and treeDef.scriptKey, "4b:61aa",
    "whose talk script is the SudowoodoScript body")

  local w = world("ROUTE_36", treeDef.x, treeDef.y - 1, save)
  w.player.facing = "down"
  w.npcs = { { cellX = treeDef.x, cellY = treeDef.y, def = treeDef } }
  eq(w:useSquirtbottle(), "squirtbottle", "facing the tree succeeds")
  local rows = w.queuedScript
  check(rows ~= nil, "_Squirtbottle QUEUES the script")
  eq(rows[1] and rows[1].op, "opentext",
    "starting at WateredWeirdTreeScript's own first row")
  local sawBattle, sawWild
  for _, cmd in ipairs(rows) do
    if cmd.op == "startbattle" then sawBattle = true end
    if cmd.op == "loadwildmon" and cmd.species == 185 and cmd.level == 20 then
      sawWild = true
    end
  end
  check(sawWild, "the slice carries loadwildmon SUDOWOODO, 20")
  check(sawBattle, "and the startbattle")
  eq(save.inventory.SQUIRTBOTTLE, 1, "a key item is never consumed")

  -- Wrong facing: the same tile relationship but looking away.
  local away = world("ROUTE_36", treeDef.x, treeDef.y - 1, save)
  away.player.facing = "up"
  away.npcs = w.npcs
  eq(away:useSquirtbottle(), "squirtbottle",
    "wItemEffectSucceeded is 1 unconditionally: the pack still quits")
  local nothing = away.queuedScript
  local isNothing
  for _, cmd in ipairs(nothing or {}) do
    if cmd.op == "rawtext" then isNothing = true end
  end
  check(isNothing, "but the queued script is the nothing-happened line")
end

-- ---- specialsound picks its cue off the item's POCKET ----------------------
--
-- Script_specialsound (engine/overworld/scripting.asm:476) farcalls
-- CheckItemPocket over wCurItem and loads SFX_GET_TM ($9b) for the TM/HM pocket,
-- SFX_ITEM ($01) for everything else.  It is the sound inside GiveItemScript, so
-- every `verbosegiveitem` rings it -- SproutTower3F's SageLiScript does
-- `verbosegiveitem HM_FLASH` and must ring the TM jingle.  The port used to
-- throw the item argument away and play SFX_ITEM unconditionally.
do
  local World = require("src.world.gen2.World")
  local rung = {}
  local sfxData = {
    -- audio/sfx_pointers.asm order, only as far as the two cues need.
    audio = { sfx = {}, sfxOrder = {} },
    items = {
      POTION = { id = "POTION", name = "POTION", pocket = "ITEM", index = 18 },
      HM_FLASH = { id = "HM_FLASH", name = "HM05", pocket = "TM_HM",
        index = 247 },
    },
  }
  for i = 0, 0x9b do sfxData.audio.sfxOrder[i + 1] = "Sfx_Unused" end
  sfxData.audio.sfxOrder[2] = "Sfx_Item"
  sfxData.audio.sfxOrder[0x9b + 1] = "Sfx_GetTm"
  local w = World.new({ data = sfxData, save = { player = {}, inventory = {} } })
  w.playSfx = function(_, id) rung[#rung + 1] = id end

  w:specialSound(247)
  eq(rung[1], 0x9b, "an HM rings SFX_GET_TM, not the ordinary item jingle")
  w:specialSound(18)
  eq(rung[2], 1, "and a POTION still rings SFX_ITEM")
  -- Script_specialsound has no operand of its own: it reads wCurItem, and a
  -- slot the cache cannot name falls to the `cp TM_HM / jr z` default.
  w:specialSound(nil)
  eq(rung[3], 1, "with no item known, the fall-through is SFX_ITEM")
  w:specialSound(0xfe)
  eq(rung[4], 1, "and so is an item index nothing in the cache names")
end

S.finish()
