package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local version = os.getenv("POKEPORT_VERSION") or "sapphire"
require("src.core.GameVersion").set(version)
require("src.import.gba.versions").select(version)
local Cache = require("tests.game3_cache")
local root = Cache.mount(version)
if not root then
  print("[skip] fishing2989 cache integration: " .. tostring(Cache.reason))
  os.exit(0)
end
local Dataset = require("src.core.game3.dataset")
local Space = require("src.core.game3.scripting.space")
local Extract = require("src.import.gba.extract_scripts")
Space.bundle = Extract.loadBundle(Dataset.cache(), root, { allowIncomplete = true })
local session = { version = version, flags = {}, vars = {} }
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }
local Text = require("src.core.game3.rom_text")
local rs = version == "ruby" or version == "sapphire"
local function check(ok, label)
  assert(ok, "FAIL fishing2989 " .. version .. " " .. label)
  print("PASS fishing2989 " .. version .. " " .. label)
end
for key, native in pairs({ gText_NotEvenANibble = "gOtherText_NotEvenANibble",
                           gText_PokemonOnHook = "gOtherText_PokeOnHook" }) do
  local ok, ir = pcall(Text.ir, key)
  check(ok and ir ~= nil, key .. "_resolves")
  if rs then
    check(Text.ascii(key) == Text.ascii(native), key .. "_is_native_rs_text")
  end
end
print("PASS fishing2989_cache_integration " .. version)
