-- the still-drawn party menu (engine/items/item_effects.asm:2022-2039)
--   luajit tests/engine/pp_restore_jingle_menu_2155.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ELIXER PP restore jingle + party menu #2155")
local check, eq = S.check, S.eq

local ItemEffects = require("src.inventory.ItemEffects")
local SaveData = require("src.core.SaveData")

local Data = {
  items = {
    ELIXER = { name = "ELIXER" }, MAX_ELIXER = { name = "MAX ELIXER" },
    ETHER = { name = "ETHER" }, MAX_ETHER = { name = "MAX ETHER" },
  },
  moves = { TACKLE = { name = "TACKLE", pp = 35 }, GROWL = { name = "GROWL", pp = 40 } },
  pokemon = { CHARMANDER = { name = "CHARMANDER" } },
  text = {},
}

local save = SaveData.newGame()

local function mon(pp1, pp2)
  return {
    species = "CHARMANDER", hp = 20, stats = { hp = 20 },
    moves = { { id = "TACKLE", pp = pp1 }, { id = "GROWL", pp = pp2 } },
  }
end

-- engine/items/item_effects.asm:2087
local target = mon(5, 5)
local result, msgs, extra = ItemEffects.use(Data, save, "ELIXER", target)
eq(result, "consumed", "a partly-drained mon consumes the ELIXER")
eq(target.moves[1].pp, 15, "every slot gets +10")
eq(target.moves[2].pp, 15, "including slot 2")
-- engine/items/item_effects.asm:2035
check(extra ~= nil and extra.useJingle == true,
      "the PP-restored line carries the Heal_Ailment jingle")
check(msgs[1]:find("PP") ~= nil, "and prints the PP restored line")

local single = mon(5, 40)
local eResult, _, eExtra = ItemEffects.use(Data, save, "ETHER", single, nil, 1)
eq(eResult, "consumed", "ETHER restores the picked move")
eq(single.moves[1].pp, 15, "slot 1 only")
eq(single.moves[2].pp, 40, "slot 2 untouched")
check(eExtra ~= nil and eExtra.useJingle == true, "ETHER carries the jingle too")

-- engine/items/item_effects.asm:2022
for _, id in ipairs({ "ELIXER", "MAX_ELIXER" }) do
  eq(ItemEffects.keepsPartyMenuOpen(id), true,
     id .. " keeps the party menu drawn through the message")
  check(ItemEffects.healsHP(id) ~= true, id .. " does not animate the HP bar")
end

-- engine/items/item_effects.asm:2120
local full = mon(35, 40)
eq((ItemEffects.use(Data, save, "MAX_ELIXER", full)), "failed",
   "a full-PP mon takes the .noEffect arm")

S.finish()
