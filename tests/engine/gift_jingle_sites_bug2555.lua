-- scripts/VermilionOldRodHouse.asm:44
-- scripts/FuchsiaGoodRodHouse.asm:44
-- scripts/Route12SuperRodHouse.asm:44
-- scripts/SSAnneCaptainsRoom.asm:77
-- scripts/SilphCo11F.asm:322
-- scripts/ViridianCity.asm:263
-- scripts/CeladonMart3F.asm:51
-- scripts/CeladonDiner.asm:58
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local unpack = table.unpack or unpack

local played = {}
package.loaded["src.core.Sound"] = {
  play = function(_, id) played[#played + 1] = id end,
}
package.loaded["src.inventory.Bag"] = {
  add = function(save, item, n)
    save.inventory[item] = (save.inventory[item] or 0) + n
    return true
  end,
}

local Commands = require("src.script.Commands")
local TextBox = require("src.render.TextBox")
local pushed = {}
TextBox.new = function(_, s, done, opts)
  return { text = s, onDone = done, opts = opts }
end

local ITEMS = {
  OLD_ROD = { name = "OLD ROD", keyItem = true },
  GOOD_ROD = { name = "GOOD ROD", keyItem = true },
  SUPER_ROD = { name = "SUPER ROD", keyItem = true },
  HM_CUT = { name = "HM01" },
  MASTER_BALL = { name = "MASTER BALL" },
  TM_DREAM_EATER = { name = "TM42" },
  TM_COUNTER = { name = "TM18" },
  COIN_CASE = { name = "COIN CASE", keyItem = true },
  POTION = { name = "POTION" },
}

local function newGame()
  return {
    data = { text = setmetatable({}, { __index = function(_, k) return k end }),
             items = ITEMS },
    save = { flags = {}, inventory = {}, player = { name = "RED" } },
    stack = { push = function(_, box) pushed[#pushed + 1] = box end },
  }
end

local function rowJingle(rows, item)
  for _, row in ipairs(rows) do
    if row[1] == "give_item" and row[2] == item then
      local game = newGame()
      local ctx = { game = game, save = game.save }
      played = {}
      Commands.give_item(ctx, select(2, unpack(row)))
      T.eq(#played, 0, item .. ": nothing plays before the received text")
      if ctx.textOpts and ctx.textOpts.auto and ctx.textOpts.auto.sound then
        ctx.textOpts.auto.sound()
      end
      return played[1]
    end
  end
  T.check(false, item .. ": give_item row found")
end

local story = require("data.scripts.story")
local story3 = require("data.scripts.story3")

T.eq(rowJingle(story3.VERMILION_OLD_ROD_HOUSE.talk
  .TEXT_VERMILIONOLDRODHOUSE_FISHING_GURU, "OLD_ROD"), "Get_Item1",
  "OLD ROD plays the plain item jingle")
T.eq(rowJingle(story3.FUCHSIA_GOOD_ROD_HOUSE.talk
  .TEXT_FUCHSIAGOODRODHOUSE_FISHING_GURU, "GOOD_ROD"), "Get_Item1",
  "GOOD ROD plays the plain item jingle")
T.eq(rowJingle(story3.ROUTE_12_SUPER_ROD_HOUSE.talk
  .TEXT_ROUTE12SUPERRODHOUSE_FISHING_GURU, "SUPER_ROD"), "Get_Item1",
  "SUPER ROD plays the plain item jingle")
T.eq(rowJingle(story.SS_ANNE_CAPTAINS_ROOM.talk
  .TEXT_SSANNECAPTAINSROOM_CAPTAIN, "HM_CUT"), "Get_Key_Item",
  "HM01 plays the key-item jingle")
T.eq(rowJingle(story.SILPH_CO_11F.talk
  .TEXT_SILPHCO11F_SILPH_PRESIDENT, "MASTER_BALL"), "Get_Key_Item",
  "MASTER BALL plays the key-item jingle")

local game = newGame()
local ctx = { game = game, save = game.save }
played = {}
Commands.give_item(ctx, "POTION", 1, false)
ctx.textOpts.auto.sound()
T.eq(played[1], "Get_Item1", "a plain item keeps the Get_Item1 default")

local story5 = require("data.scripts.story5")
local function giftJingle(map, label)
  pushed = {}
  played = {}
  local g = newGame()
  story5[map].talk[label](g, nil, nil, function() end)
  while #pushed > 0 do
    local box = table.remove(pushed, 1)
    if box.opts and box.opts.auto and box.opts.auto.sound then
      box.opts.auto.sound()
      return played[1]
    end
    if box.onDone then box.onDone() end
  end
end

T.eq(giftJingle("VIRIDIAN_CITY", "TEXT_VIRIDIANCITY_FISHER"), "Get_Item2",
  "TM42 plays Get_Item2")
T.eq(giftJingle("CELADON_MART_3F", "TEXT_CELADONMART3F_CLERK"), "Get_Item1",
  "TM18 keeps Get_Item1")
T.eq(giftJingle("CELADON_DINER", "TEXT_CELADONDINER_GYM_GUIDE"),
  "Get_Key_Item", "the coin case keeps Get_Key_Item")

T.finish("gift_jingle_sites_bug2555")
