local M = {}

M.ROWS = {
  [1] = { name = "MASTER BALL", pocket = "POKE_BALLS", fieldUse = "battle" },
  [4] = { name = "POKé BALL", pocket = "POKE_BALLS", fieldUse = "battle" },
  [13] = { name = "POTION", pocket = "ITEMS", fieldUse = "heal" },
  [139] = { name = "ORAN BERRY", pocket = "BERRY_POUCH", fieldUse = "heal" },
  [261] = { name = "ITEMFINDER", pocket = "KEY_ITEMS", fieldUse = "itemfinder" },
  [362] = { name = "VS SEEKER", pocket = "KEY_ITEMS", fieldUse = "vs_seeker" },
  [364] = { name = "TM CASE", pocket = "KEY_ITEMS", fieldUse = "key" },
  [365] = { name = "BERRY POUCH", pocket = "KEY_ITEMS", fieldUse = "key" },
}

function M.install()
  local ItemsData = require("src.core.game3.items_data")
  if pcall(ItemsData.ensureLoaded) then return false end
  ItemsData.installPack({ count = 8, items = M.ROWS })
  return true
end

return M
