package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local version = os.getenv("POKEPORT_VERSION") or "sapphire"
require("src.core.GameVersion").set(version)
require("src.import.gba.versions").select(version)
local Cache = require("tests.game3_cache")
local root = Cache.mount()
if not root then
  print("[skip] flash2762 cache integration: " .. tostring(Cache.reason))
  os.exit(0)
end
local Dataset = require("src.core.game3.dataset")
local Profile = require("src.core.game3.profile").of(version)
local Space = require("src.core.game3.scripting.space")
local Extract = require("src.import.gba.extract_scripts")
Space.bundle = Extract.loadBundle(Dataset.cache(), root, { allowIncomplete = true })
if Profile.field and Profile.field.flashScript then
  assert(Space.installLabels(Space.bundle, Dataset.cache(), root))
end
local session = { version = version, flags = {}, vars = {} }
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }
local showDone
package.loaded["src.core.game3.field_move_show_mon"] = { start = function(_, _, fn) showDone = fn end }
local Flags = require("src.core.game3.scripting.flags")
local Moves = require("src.core.game3.field_moves")
local Field = require("src.core.game3.field")
local View = require("src.core.game3.field_view")
local Fx = require("src.core.game3.field_effects")
local Text = require("src.core.game3.rom_text")
Space.store = Flags.newStore({ flags = session.flags })
session.flags = Space.store.flags
Space.vm = require("src.core.game3.scripting.vm").new({ scripts = Space.bundle.scripts, store = Space.store })
Field._session = session
Fx._cache = Dataset.cache()
local function check(ok, label)
  assert(ok, "FAIL flash2762 " .. version .. " " .. label)
  print("PASS flash2762 " .. version .. " " .. label)
end
Flags.setFlag(Space.store, nil, Moves.badgeFlag("FLASH"), true)
local ctx = { session = session, store = Space.store, isCave = true }
local payload = Moves.flashFromMenu(ctx)
check(payload.ok, "first_use_available")
View.setFlashLevel(4)
Fx._anims = {}
Field.executeFieldMove(payload)
showDone()
check(Field.locked and Flags.getFlag(Space.store, nil, payload.flag), "animation_locked_and_active")
for _ = 1, 600 do Fx.step(); Space.vm:tick() end
local rse = Profile.family == "rse"
check(View.getFlashLevel() == (rse and 1 or 0), "first_use_cart_level")
check(View.flashRadius() == (rse and 72 or nil), "first_use_cart_radius")
check(not Field.locked and not Space.vm:isRunning(), "animation_end_unlocks_field")
local key = (version == "ruby" or version == "sapphire") and "OtherText_CantUseThatHere" or "gText_InUseAlready_PM"
local expected = Text.ascii(key)
local res = Moves.flashFromMenu(ctx)
check(not res.ok and res.text == expected, "repeated_flash_exact_cached_prompt")
local game = { session = session, data = { maps = Dataset.buildMaps() } }
local floors = 0
for mapId, def in pairs(game.data.maps) do
  if tonumber(def.cave) == 1 then
    Field.clearTempFieldEventData(game, mapId)
    View.setDefaultFlashLevel(game, mapId)
    check(Flags.getFlag(Space.store, nil, payload.flag) and View.getFlashLevel() == (rse and 1 or 0),
      "dark_floor_persists_" .. mapId)
    floors = floors + 1
    if floors == 2 then break end
  end
end
check(floors == 2, "two_actual_cached_dark_floors")
print("PASS flash2762_cache_integration " .. version)
