package.path = "./?.lua;./?/init.lua;" .. package.path

local Bag = require("src.core.game3.bag")
local Flags = require("src.core.game3.scripting.flags")
local Space = require("src.core.game3.scripting.space")

local FLAG = 0x847
local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

print("=== game3 FLAG_SYS_GOT_BERRY_POUCH ===")

check(Bag.FLAG_SYS_GOT_BERRY_POUCH == FLAG, "flag id is 0x847")

do
  Space.store = Flags.newStore()
  local bag = Bag.new()
  local ok = Bag.add(bag, 139, 1)
  check(ok, "ORAN BERRY added")
  check(Bag.has(bag, 365, 1), "BERRY POUCH auto-granted")
  check(Flags.getFlag(Space.store, nil, FLAG), "berry add sets FLAG_SYS_GOT_BERRY_POUCH")
end

do
  Space.store = Flags.newStore()
  local bag = Bag.new()
  Bag.add(bag, 365, 1)
  check(Flags.getFlag(Space.store, nil, FLAG), "adding BERRY POUCH directly sets the flag")
end

do
  Space.store = Flags.newStore()
  local bag = Bag.new()
  Bag.add(bag, 13, 1)
  check(not Flags.getFlag(Space.store, nil, FLAG), "non-berry add leaves the flag clear")
end

local function activate(session)
  Space.active = false
  Space.mapId = nil
  Space.bundle = Space.bundle or { scripts = {}, text = {}, movements = {}, events = {} }
  local game = { session = session, data = { maps = {} } }
  local ok, err = pcall(Space.activate, nil, "CERULEAN_CITY_HOUSE5", game, nil)
  if not ok then print("  activate error: " .. tostring(err)) end
  local on = Space.store and Flags.getFlag(Space.store, nil, FLAG)
  pcall(Space.deactivate, nil)
  Space.store = nil
  return on
end

do
  Space.store = nil
  local bag = Bag.new()
  bag.pockets.KEY_ITEMS[1] = { id = 365, qty = 1 }
  bag.pockets.BERRY_POUCH[1] = { id = 139, qty = 3 }
  local session = { bag = bag, flags = {}, vars = {} }
  check(activate(session) == true, "old save holding BERRY POUCH gets the flag on map load")
end

do
  local session = { bag = Bag.new(), flags = {}, vars = {} }
  check(not activate(session), "save without BERRY POUCH keeps the flag clear on map load")
end

do
  Space.store = Flags.newStore()
  local session = { bag = Bag.new(), flags = {}, vars = {} }
  Bag.add(session.bag, 139, 1)
  Space.persistSession(nil, { session = session })
  Space.store = nil
  check(session.flags[tostring(FLAG)] == true, "persistSession writes the flag into session.flags")
  local reloaded = { bag = Bag.new(), flags = session.flags, vars = session.vars }
  check(activate(reloaded) == true, "flag survives save and reload without the bag backfill")
end

if failed > 0 then
  print(string.format("%d check(s) failed", failed))
  os.exit(1)
end
print("all passed")
