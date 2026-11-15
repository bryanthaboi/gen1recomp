--
--   luajit tests/gen2_s7b_rom_text_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 s7b rom text")
local check, eq = S.check, S.eq

love = require("tests.love_stub")
require("src.core.Logger").warn = function() end

local Fixture = require("tests.fixture_data.gen2_rom_text_s7_b")
local BattleState = require("src.ui.gen2.BattleState")
local BattleTowerMenu = require("src.ui.gen2.BattleTowerMenu")
local Effects = require("src.battle.gen2.Effects")
local EvolutionAnim = require("src.ui.gen2.EvolutionAnim")
local HallOfFame = require("src.ui.gen2.HallOfFame")
local Prize = require("src.battle.gen2.Prize")

local function data(extra, version)
  return { text = Fixture.text(extra, version) }
end

local function without(label, version)
  return { text = Fixture.without(label, version) }
end

local function screen(d, fields)
  local state = { game = { data = d } }
  for key, value in pairs(fields or {}) do state[key] = value end
  return setmetatable(state, { __index = BattleState })
end

do
  eq(BattleState.battleStartText(data({ WildPokemonAppearedText = "W {STRBUF}!{PROMPT}" }),
    "RATTATA", nil), "W RATTATA!", "WildPokemonAppearedText is read from data.text")
  check(not pcall(BattleState.battleStartText, without("WildPokemonAppearedText"),
    "RATTATA", nil), "and its absence is an error")
end

do
  local state = screen(data({ ["BattleMenuHeader.Text#3"] = "SAC" }), { contest = false })
  eq(state:menuLabels()[3], "SAC", "BattleMenuHeader.Text#3 is the PACK label")
  check(not pcall(state.menuLabels, screen(without("BattleMenuHeader.Text#1"), {})),
    "a cache without BattleMenuHeader.Text#1 is an error")
  eq(screen(data({ BrnString = "BRL" })):statusTag({ status = "burn" }, "player"), "BRL",
    "the HUD status tag is BrnString")
  eq(screen(data({ ChooseAMonString = "PICK" })):rom("ChooseAMonString"), "PICK",
    "BattleState:rom reads data.text")
  local hm = screen({ pokemon = { tmhmMoves = Fixture.tmhmMoves } })
  check(hm:isHMMove("WHIRLPOOL") and not hm:isHMMove("NIGHTMARE"),
    "IsHMMove reads HM01-HM07 out of pokemon.lua tmhmMoves")
  check(not pcall(hm.isHMMove, screen({ pokemon = {} }), "CUT"),
    "a cache without tmhmMoves is an error")
end

do
  local d = data({ DownpourText = "RAIN{PROMPT}", _BattleFlewText = "\nUP!{PROMPT}" })
  eq(Effects.weatherText(d, "start", "rain"), "RAIN", "weather lines come from data.text")
  eq(Effects.chargeText(d, "EFFECT_FLY", "FLY", "PIDGEY"), "PIDGEY\nUP!",
    "charge lines come from data.text")
  check(not pcall(Effects.weatherText, without("DownpourText"), "start", "rain"),
    "a missing weather label is an error")
  eq(Effects.stageMessage(data({ _BattleStatWentUpText = " UP!{PROMPT}" }), "PIDGEY", "attack", 1),
    "PIDGEY's\nATTACK UP!", "stat stage lines come from data.text")
  eq(Effects.stageMessage(data({ ["StatNames#4"] = "SPATK" }), "PIDGEY", "specialAttack", -2),
    "PIDGEY's\nSPATK\rsharply fell!", "the stat name is StatNames#n and the scroll is the cache's")
  check(not pcall(Effects.statName, without("StatNames#7"), "evasion"),
    "a missing StatNames row is an error")
end

do
  eq(Prize.message(data({ SentAllToMomText = "ALL{PROMPT}" }), { total = 1, mode = 3 }, "GOLD"),
    "ALL", "SentAllToMomText is read from data.text")
  check(not pcall(Prize.payDayMessage, without("BattleText_PlayerPickedUpPayDayMoney"), 5, "GOLD"),
    "a missing Pay Day label is an error")
end

do
  local mon = { species = "OLD", nickname = "NICK", moves = {} }
  local anim = EvolutionAnim.new({ data = { audio = {},
    text = Fixture.text({ _EvolvingText = "EVO {STRBUF}\nNOW{DONE}" }) } },
    { mon = mon, entry = { into = "NEW" }, party = { mon } })
  eq(anim.lines[1], "EVO NICK", "_EvolvingText is read from data.text")
  check(not pcall(EvolutionAnim.new, { data = { audio = {}, text = Fixture.without("_EvolvingText") } },
    { mon = mon, entry = { into = "NEW" }, party = { mon } }), "and its absence is an error")
end

do
  local save = { player = { name = "GOLD", id = 1 }, playTime = { hours = 1, minutes = 2 } }
  eq(HallOfFame.at(HallOfFame.playerPlacements(save,
    data({ ["HOF_AnimatePlayerPic.PlayTime"] = "TIME" })), 1, 8), "TIME",
    "HOF_AnimatePlayerPic.PlayTime is read from data.text")
  check(not pcall(HallOfFame.playerPlacements, save, without("HOF_AnimatePlayerPic.PlayTime")),
    "and its absence is an error")
end

do
  local game = { data = data({ Text_WhatLevelDoYouWantToChallenge = "LEVEL?{DONE}" }, "crystal") }
  local rows = { { group = 1 }, { group = 2 }, { group = 3 }, { group = 4 } }
  local menu = BattleTowerMenu.new(game, { save = {}, party = {}, rows = rows })
  eq(menu.message, "LEVEL?", "Text_WhatLevelDoYouWantToChallenge is read from data.text")
  eq(menu:rowLabel(5), "CANCEL", "Strings_Ll0ToL40 supplies the CANCEL row")
  menu.party = { { species = "LUGIA", level = 40 } }
  menu.monName = function(id) return id end
  menu.cursor = 4
  menu:confirm()
  eq(menu.pages and menu.pages[1], "LUGIA may go\nonly to BATTLE", "Text_UberRestriction is read from data.text")
  check(not pcall(BattleTowerMenu.new, { data = without("Text_WhatLevelDoYouWantToChallenge", "crystal") },
    { save = {}, party = {}, rows = rows }), "and its absence is an error")
end

S.finish()
