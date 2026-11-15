-- pokered engine/battle/core.asm:2315 (#1901)

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq
love = love or require("tests.love_stub")

local PartyMenu = require("src.ui.PartyMenu")

local game = {
  data = { text = dofile("tests/fixture_data/text.lua"), pokemon = { LAPRAS = { name = "LAPRAS" } } },
  save = {
    party = { { species = "LAPRAS", hp = 50, stats = { hp = 50 },
                level = 30, moves = {} } },
    inventory = {}, options = {}, flags = {},
  },
}
game.stack = { states = {},
  push = function(self, s) table.insert(self.states, s) end,
  pop = function(self) return table.remove(self.states) end,
  top = function(self) return self.states[#self.states] end }

local battle = { playerParty = game.save.party }

local function message(opts)
  return PartyMenu.new(game, opts):bottomMessage()
end

eq(message({}), "Choose a POKéMON.",
   "field START -> POKéMON is NORMAL_PARTY_MENU")
eq(message({ battle = battle }), "Choose a POKéMON.",
   "the voluntary PKMN option is NORMAL_PARTY_MENU too")
eq(message({ battle = battle, forceSwitch = true }),
   "Bring out which\nPOKéMON?",
   "ChooseNextMon / SHIFT is BATTLE_PARTY_MENU")
eq(message({ battle = battle, itemUse = true }),
   "Use item on which\nPOKéMON?",
   "in-battle medicine keeps USE_ITEM_PARTY_MENU")
eq(message({ tmhm = { move = "FIX_CUT", kind = "TM" } }),
   "Use TM on which\nPOKéMON?", "TMHM_PARTY_MENU")

game.data.text._PartyMenuNormalText = "CHOOSE A #MON."
game.data.text._PartyMenuBattleText = "BRING OUT WHICH #MON?"
eq(message({ battle = battle }), "CHOOSE A #MON.",
   "the voluntary open prints PartyMenuNormalText")
eq(message({ battle = battle, forceSwitch = true }), "BRING OUT WHICH #MON?",
   "the forced open prints PartyMenuBattleText")

T.finish("party_battle_prompt_bug1901")
