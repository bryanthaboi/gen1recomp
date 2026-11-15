package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local version = os.getenv("POKEPORT_VERSION") or "sapphire"
require("src.core.GameVersion").set(version)
require("src.import.gba.versions").select(version)
local Cache = require("tests.game3_cache")
local root = Cache.mount(version)
if not root then
  print("[skip] itemfinder3018 cache integration: " .. tostring(Cache.reason))
  os.exit(0)
end
local Dataset = require("src.core.game3.dataset")
local Space = require("src.core.game3.scripting.space")
local Extract = require("src.import.gba.extract_scripts")
Space.bundle = Extract.loadBundle(Dataset.cache(), root, { allowIncomplete = true })
local session = { version = version, flags = {}, vars = {} }
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }
local Text = require("src.core.game3.rom_text")
local Itemfinder = require("src.core.game3.itemfinder")
local rs = version == "ruby" or version == "sapphire"
local function check(ok, label)
  assert(ok, "FAIL itemfinder3018 " .. version .. " " .. label)
  print("PASS itemfinder3018 " .. version .. " " .. label)
end
-- pokeruby/src/item_use.c:281, :561, :577
local NATIVE_RS = {
  nothing = "gOtherText_NoResponse",
  nearby = "gOtherText_ItemfinderResponding",
  onTop = "gOtherText_ItemfinderItemUnderfoot",
}
for _, kind in ipairs({ "nothing", "nearby", "onTop" }) do
  for _, s in ipairs({ session, false }) do
    local key = Itemfinder.textKey(kind, s or nil)
    local ok, ir = pcall(Text.ir, key)
    check(ok and ir ~= nil, kind .. (s and "_session" or "_task") .. "_resolves")
    if rs then
      check(Text.ascii(key) == Text.ascii(NATIVE_RS[kind]), kind .. (s and "_session" or "_task") .. "_is_native_rs_text")
    end
  end
end
print("PASS itemfinder3018_cache_integration " .. version)
