-- #1635: PrintItemUseTextAndRemoveItem items must request Heal_Ailment
-- via extra.useJingle after the "X used Y!" line.
--
-- ROM-free: stubs items/text only (CI headless has no data/generated/).
--
--   luajit tests/engine/item_use_jingle_bug1635.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("item use Heal_Ailment jingle #1635")
local check, eq = S.check, S.eq

local ItemEffects = require("src.inventory.ItemEffects")
local SaveData = require("src.core.SaveData")

local ITEM_IDS = {
  "REPEL", "SUPER_REPEL", "MAX_REPEL",
  "X_ATTACK", "X_DEFEND", "X_SPEED", "X_SPECIAL",
  "X_ACCURACY", "DIRE_HIT", "GUARD_SPEC", "POKE_DOLL",
}

local Data = { items = {}, text = setmetatable({
  _ItemUseText001 = "{PLAYER} used{DONE}",
  _ItemUseText002 = "{RAM:wStringBuffer}!{DONE}",
}, { __index = dofile("tests/fixture_data/text.lua") }) }
for _, id in ipairs(ITEM_IDS) do
  Data.items[id] = { name = id:gsub("_", " ") }
end

local save = SaveData.newGame()
save.player.name = "RED"

local function battleStub(playerName)
  return {
    kind = "wild",
    player = {
      name = playerName or "PIKACHU",
      stages = { attack = 0, defense = 0, speed = 0, special = 0, accuracy = 0 },
      mon = {},
    },
    enemy = { name = "RATTATA" },
  }
end

local function assertJingle(itemId, battle)
  local result, msgs, extra = ItemEffects.use(Data, save, itemId, nil, battle)
  check(result == "consumed" or result == "consumed_escape",
        itemId .. " succeeds (" .. tostring(result) .. ")")
  check(extra and extra.useJingle, itemId .. " sets useJingle")
  check(msgs and msgs[1] and msgs[1]:find("used"),
        itemId .. " prints used line")
  return result, msgs, extra
end

for _, id in ipairs({ "REPEL", "SUPER_REPEL", "MAX_REPEL" }) do
  assertJingle(id, nil)
end

local b = battleStub()
for _, id in ipairs({
  "X_ATTACK", "X_DEFEND", "X_SPEED", "X_SPECIAL",
  "X_ACCURACY", "DIRE_HIT", "GUARD_SPEC",
}) do
  local _, _, extra = assertJingle(id, b)
  if id == "X_ATTACK" then
    check(extra.afterMessages and #extra.afterMessages > 0,
          "X_ATTACK follows used line with effect text")
  end
end

local _, _, dollExtra = assertJingle("POKE_DOLL", battleStub())
eq(dollExtra.afterMessages, nil, "Poké Doll is used-line only")

S.finish()
