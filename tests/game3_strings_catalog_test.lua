#!/usr/bin/env luajit
-- Game3 hands the merged mod data to Strings.load, like Game and Game2, so a
-- translation mod's `strings` registry is what Strings() answers from.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local merged = { YES = "OUI" }
package.loaded["src.mods.Loader"] = {
  new = function()
    return {
      load = function(_, data) data.strings = merged end,
      status = function() return {} end,
    }
  end,
}
package.loaded["src.mods.Gen3Compat"] = { applyMerged = function() end }

local Strings = require("src.core.Strings")
Strings.load({ strings = { YES = "LAUNCHER" } }) -- the launcher's preload
local Game3 = require("src.core.Game3")
local game = { data = {} }
Game3._loadMods(game, {})

check(Strings("YES") == "OUI", "Strings() answers from the merged catalog after mods load")
check(Strings("NO") == "NO", "an untranslated key still falls back to English")

print(("game3_strings_catalog_test: %s (%d failed)"):format(failed == 0 and "PASS" or "FAIL", failed))
if failed > 0 then os.exit(1) end
