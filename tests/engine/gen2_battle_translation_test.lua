-- Gen 2's battle engine and battle screen must look up authored text at the
-- point it is emitted/drawn.  Names stay runtime arguments; the catalog keys
-- are stable English templates that modkit can harvest.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

love = require("tests.love_stub")
require("src.core.Logger").warn = function() end

local Strings = require("src.core.Strings")
local Effects = require("src.battle.gen2.Effects")
local Battle = require("src.battle.gen2.Battle")
local BattleState = require("src.ui.gen2.BattleState")
local Chrome = require("src.ui.gen2.Chrome")
local GbcPalette = require("src.render.GbcPalette")

Strings.load({ strings = {
  ["%s must recharge!"] = "%s doit recharger!",
  ["%s's %s sharply rose!"] = "%s: %s monte beaucoup!",
  ["%s's %s was disabled!"] = "%s: %s neutralisee!",
  ["%s TRANSFORMED into %s!"] = "%s copie %s!",
  ["%s used %s!"] = "%s emploie %s!",
  ["It started to rain!"] = "La pluie commence!",
  ["%s fell asleep!"] = "%s s'endort!",
  ["%s was poisoned!"] = "%s est empoisonne!",
  ["%s was badly poisoned!"] = "%s est gravement empoisonne!",
  ["%s is paralyzed! It may be unable to move!"] = "%s est paralyse!",
  ["%s was burned!"] = "%s est brule!",
  ["%s was frozen solid!"] = "%s est gele!",
  ["%s is hurt by poison!"] = "%s souffre du poison!",
  ["ATTACK"] = "ATTAQUE",
  ["FIGHT"] = "COMBAT",
  ["<PK><MN>"] = "EQUIPE",
  ["PACK"] = "SAC",
  ["RUN"] = "FUITE",
  ["YES"] = "OUI",
  ["NO"] = "NON",
  ["PSN"] = "PSN-CATALOGUE",
  -- Registry-authored display values and already formatted messages must not
  -- be fed through the source catalog a second time.
  ["PSN-FR"] = "MAUVAISE-SECONDE-TRADUCTION",
  ["OVERRIDE"] = "OVR-FR",
  ["CUSTOM"] = "NOUVEAU-FR",
  ["TYPE LOCALISE"] = "MAUVAIS-TYPE-RETRADUIT",
  ["%s is already out."] = "%s SORT DEJA.",
  ["PIKA SORT DEJA."] = "MAUVAISE-SECONDE-TRADUCTION",
  ["There's no will to battle!"] = "AUCUNE VOLONTE!",
  ["AUCUNE VOLONTE!"] = "MAUVAISE-SECONDE-TRADUCTION",
  ["PARKBALL\xc3\x97%02d"] = "BALLS:%02d",
} })

local function battleStub(data)
  local player = { nickname = "DITTO", species = "DITTO", hp = 20,
    maxHp = 20, stats = {}, moves = {}, volatile = {} }
  local enemy = { nickname = "CIBLE", species = "RAW_SPECIES", hp = 20,
    maxHp = 20, stats = {}, moves = {}, volatile = {} }
  local battle = setmetatable({
    data = data or {}, events = {}, player = player, enemy = enemy,
    party = { player }, enemyParty = { enemy },
    screens = { player = {}, enemy = {} },
    stages = { player = Battle.newStages(), enemy = Battle.newStages() },
    random = function() return 0 end,
  }, { __index = Battle })
  return battle, player, enemy
end

do
  local function recharge(overrides)
    local text = require("tests.gen2_battle_text_fixture")()
    for label, line in pairs(overrides or {}) do text[label] = line end
    local mon = { nickname = "PIKACHU", volatile = { recharge = true } }
    local battle = setmetatable({ data = { text = text }, events = {},
      player = mon }, { __index = Battle })
    T.check(not battle:canAct(mon), "recharge still spends the turn")
    return battle.events[1] and battle.events[1].text
  end
  T.eq(recharge(), "PIKACHU\nmust recharge!",
    "the untranslated cache line carries the runtime battler name")
  T.eq(recharge({ MustRechargeText = "{USER} doit recharger!" }),
    "PIKACHU doit recharger!",
    "a translated cache line replaces the English one and still receives the battler name")
end

local S7B = require("tests.fixture_data.gen2_rom_text_s7_b")
local S7A = require("tests.fixture_data.gen2_rom_text_s7_a")
T.eq(Effects.stageMessage({ text = S7B.text({
    Text_BattleEffectActivate = "{USER}:\n{STRBUF}", ["StatNames#1"] = "ATTAQUE",
    _BattleStatWentWayUpText = "\rmonte beaucoup!{PROMPT}" }) }, "PIKACHU", "attack", 2),
  "PIKACHU:\nATTAQUE\rmonte beaucoup!",
  "the stage template and the stat label both come from the cache")

do
  local data = {
    moves = { RAW_MOVE = { name = "JOLI MOUV" } },
    items = { RAW_ITEM = { name = "BEL OBJET" } },
    pokemon = {
      DITTO = { name = "METAMORPH", types = { "NORMAL" } },
      RAW_SPECIES = { name = "BELLE ESPECE", types = { "NORMAL" } },
    },
    text = S7A.text({
      WasDisabledText = "{TARGET}: {STRBUF} neutralisee!{PROMPT}",
      TransformedText = "{USER} copie {STRBUF}!{PROMPT}",
      EnemyUsedOnText = "{ENEMY} emploie {STRBUF} sur {STRBUF}!{PROMPT}",
    }),
  }
  local battle, player, enemy = battleStub(data)
  enemy.moves = { { id = "RAW_MOVE", pp = 5 } }
  enemy.volatile.lastMove = "RAW_MOVE"
  Battle.MOVE_EFFECTS.EFFECT_DISABLE(battle, player, enemy)
  T.eq(battle.events[#battle.events].text, "Enemy CIBLE: JOLI MOUV neutralisee!",
    "a translated WasDisabledText receives the move's display name, not its id")

  battle.events = {}
  Battle.MOVE_EFFECTS.EFFECT_TRANSFORM(battle, player, enemy)
  T.eq(battle.events[1].text, "DITTO copie BELLE ESPECE!",
    "TransformedText keeps the actor name and resolves the target species name")

  battle.events = {}
  battle.trainer = { name = "DRESSEUR", items = { "RAW_ITEM" } }
  battle:enemyUseItem("RAW_ITEM")
  T.eq(battle.events[#battle.events].text, "DRESSEUR emploie BEL OBJET sur CIBLE!",
    "EnemyUsedOnText gets the item's display name and the foe's nickname")

  battle.events = {}
  battle.data.text = S7B.text({ DownpourText = "La pluie commence!{PROMPT}" })
  Battle.MOVE_EFFECTS.EFFECT_RAIN_DANCE(battle, player, enemy)
  T.eq(battle.events[1].text, "La pluie commence!",
    "the weather line is the cache's DownpourText")
end

do
  local expected = {
    sleep = "MON s'endort!",
    poison = "MON est empoisonne!",
    toxic = "MON est gravement empoisonne!",
    paralyze = "MON est paralyse!",
    burn = "MON est brule!",
    freeze = "MON est gele!",
  }
  local text = S7A.text({
    FellAsleepText = "{TARGET} s'endort!{PROMPT}",
    WasPoisonedText = "{TARGET} est empoisonne!{PROMPT}",
    BadlyPoisonedText = "{TARGET} est gravement empoisonne!{PROMPT}",
    ParalyzedText = "{TARGET} est paralyse!{PROMPT}",
    WasBurnedText = "{TARGET} est brule!{PROMPT}",
    WasFrozenText = "{TARGET} est gele!{PROMPT}",
    HurtByPoisonText = "{USER} souffre du poison!{PROMPT}",
  })
  for status, want in pairs(expected) do
    local battle = battleStub({ text = text })
    local mon = { nickname = "MON", hp = 16, maxHp = 16, volatile = {} }
    battle.player = mon
    T.check(battle:applyStatus(mon, status), status .. " can be inflicted")
    T.eq(battle.events[#battle.events].text, want,
      status .. " uses its translated cache line")
  end

  local battle = battleStub({ text = text })
  local mon = { nickname = "MON", hp = 16, maxHp = 16,
    status = "poison", volatile = {} }
  battle.player = mon
  battle:tickStatus(mon)
  T.eq(battle.events[1].text, "MON souffre du poison!",
    "the residual line is the cache's translated HurtByPoisonText")
end

do
  local Registry = require("src.mods.Registry")
  local Schemas = require("src.mods.Schemas")
  local statuses = Registry.new("statuses", Schemas.REGISTRIES.statuses)
  statuses.base = function() return Battle.STATUSES end
  -- This is the exact label-only patch translation mods author.  The vanilla
  -- record must not retain a redundant hudLabel that shadows the patch.
  statuses:patch("poison", { label = "PSN-FR" }, "translation")
  statuses:register("custom", { id = "custom", label = "CUSTOM" }, "mod")
  statuses:register("hidden", {
    id = "hidden", label = "CUSTOM", substatus = true,
  }, "mod")
  local merged = {}
  for id in pairs(Battle.STATUSES) do merged[id] = statuses:get(id) end
  merged.custom = statuses:get("custom")
  merged.hidden = statuses:get("hidden")

  T.eq(merged.poison.hudLabel, nil,
    "a real label-only Registry patch has no stale vanilla hudLabel")
  local state = setmetatable({ contest = false,
    game = { data = { gen2Statuses = merged, text = S7B.text({
      ["BattleMenuHeader.Text#1"] = "COMBAT", ["BattleMenuHeader.Text#2"] = "EQUIPE",
      ["BattleMenuHeader.Text#3"] = "SAC", ["BattleMenuHeader.Text#4"] = "FUITE",
      ["ContestBattleMenuHeader.Text#3"] = "BALLS:  ", PsnString = "PSN-ROM" }) } },
  }, { __index = BattleState })
  T.same(state:menuLabels(), { "COMBAT", "EQUIPE", "SAC", "FUITE" },
    "the four battle menu labels come from BattleMenuHeader.Text in the cache")
  T.eq(state:statusTag({ status = "poison" }, "player"), "PSN-FR",
    "a label-only registry patch controls the HUD without a second lookup")
  T.eq(state:statusTag({ status = "custom" }, "player"), "CUSTOM",
    "a newly registered status label is complete authored display content")
  T.eq(state:statusTag({ status = "hidden" }, "player"), nil,
    "a modded substatus remains absent from the major-status HUD slot")

  state.contest = true
  state.save = { bugContest = { balls = 7 } }
  T.eq(state:menuLabels()[3], "BALLS:07",
    "PrintParkBallsRemaining writes the count over the cache label's last two tiles")

  state.game.data.gen2Statuses = nil
  T.eq(state:statusTag({ status = "poison" }, "player"), "PSN-ROM",
    "with no registry the HUD tag is the cache's PsnString")
  state.game = nil
  T.check(not pcall(state.statusTag, state, { status = "poison" }, "player"),
    "and with no dataset at all it is an error, not the strings catalog")
  T.eq(state:statusTag({ status = "confuse" }, "player"), nil,
    "built-in confusion remains a substatus and never gets a HUD tag")
end

do
  local state = setmetatable({ game = { data = { text = S7B.text({
    BattleText_MonIsAlreadyOut = "{STRBUF} SORT DEJA.{PROMPT}",
    BattleText_TheresNoWillToBattle = "AUCUNE VOLONTE!{PROMPT}" }) } } },
    { __index = BattleState })
  state:refuseSwitch(false, "BattleText_MonIsAlreadyOut", "PIKA")
  T.eq(state.message, "PIKA SORT DEJA.",
    "refuseSwitch translates and formats its source exactly once")
  state:refuseShift()
  T.eq(state.message, "AUCUNE VOLONTE!",
    "refuseShift does not look up its translated fallback a second time")
end

do
  local drawn = {}
  local originalPrint = Chrome.printThrough
  Chrome.printThrough = function(text) drawn[#drawn + 1] = text end
  local state = setmetatable({
    game = { data = {
      moves = { MOD_MOVE = { type = "MOD_TYPE" } },
      text = require("tests.gen2_battle_text_fixture")(), type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(), types = {
        MOD_TYPE = { name = "TYPE LOCALISE", category = "special" },
      } },
    } },
    battle = {
      player = {},
      moveDisabled = function() return false end,
    },
  }, { __index = BattleState })
  state:drawMoveInfoBox({ id = "MOD_MOVE", pp = 3, maxPp = 5 })
  Chrome.printThrough = originalPrint
  local seen = {}
  for _, text in ipairs(drawn) do seen[text] = true end
  T.check(seen["TYPE LOCALISE"],
    "the TYPE/ box uses the live type registry display name verbatim")
  T.check(not seen["MOD_TYPE"] and not seen["MAUVAIS-TYPE-RETRADUIT"],
    "the TYPE/ box renders neither the raw id nor a second catalog lookup")
end

do
  local drawn = {}
  Chrome.clear = function() end
  Chrome.paletteBox = function() end
  Chrome.cursorThrough = function() end
  Chrome.printThrough = function(text) drawn[#drawn + 1] = text end
  GbcPalette.setBgp = function() return nil end

  local state = setmetatable({
    game = { data = { text = S7B.text({ ["YesNoMenuHeader.MenuData#1"] = "OUI",
      ["YesNoMenuHeader.MenuData#2"] = "NON" }) } },
    battle = { player = {}, enemy = {} },
    phase = "ask-nickname", messageTimer = 0, nicknameIndex = 1,
    palettes = { battleText = {
      { 255, 255, 255 }, { 140, 156, 255 }, { 115, 132, 255 }, { 0, 0, 0 },
    } },
    bottomUIVisible = function() return true end,
    drawHud = function() end,
    printMessage = function() end,
  }, { __index = BattleState })
  state:drawPanel()
  local seen = {}
  for _, text in ipairs(drawn) do seen[text] = true end
  T.check(seen.OUI and seen.NON,
    "battle YES/NO choices are YesNoMenuHeader's cache strings")
end

Strings.load({})
T.check(not Strings.active(), "the catalog is unloaded after the test")

T.finish("gen2 battle translation")
