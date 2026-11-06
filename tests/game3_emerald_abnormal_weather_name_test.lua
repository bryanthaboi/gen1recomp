#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local function emeraldRoot()
  local home, identity = os.getenv("HOME"), os.getenv("POKEPORT_IDENTITY")
  if not (home and identity and identity ~= "") then return nil end
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE", home .. "/.local/share/love" }) do
    local root = base .. "/" .. identity .. "/emerald/"
    local f = io.open(root .. "data/generated/gba/rse/region_map/manifest.lua", "rb")
    if f then
      f:close()
      return root
    end
  end
  return nil
end

local ROOT = emeraldRoot()
if not ROOT then
  print("[skip] no emerald cache under POKEPORT_IDENTITY")
  os.exit(0)
end

local function readFile(rel)
  local f = io.open(ROOT .. rel, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

_G.love = { filesystem = {
  getInfo = function(p) if readFile(p) then return {} end end,
  load = function(p) return loadfile(ROOT .. p) end,
} }
local fs = {}
function fs:read(rel) return readFile(rel) end
function fs:exists(rel) return readFile(rel) ~= nil end
package.loaded["src.core.game3.dataset"] = { cache = function() return fs end, mountExtractRoots = function() end }
require("src.core.GameVersion").set("emerald")

local session = { version = "emerald", party = {}, flags = {}, vars = {}, store = { flags = {}, vars = {} } }
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }
package.loaded["src.core.game3.scripting.space"] = { store = session.store }

local Natives = require("src.core.game3.scripting.natives")
Natives.bind("emerald")
local C = require("src.core.game3.constants").of("emerald")
local Flags = require("src.core.game3.scripting.flags")
local VAR = C:require("vars", "VAR_ABNORMAL_WEATHER_LOCATION")
local SPECIAL = C.specials.byName.GetAbnormalWeatherMapNameAndType

-- pokeemerald/src/field_specials.c:3472
local want = {
  "ROUTE 114", "ROUTE 114", "ROUTE 115", "ROUTE 115", "ROUTE 116", "ROUTE 116", "ROUTE 118", "ROUTE 118",
  "ROUTE 105", "ROUTE 105", "ROUTE 125", "ROUTE 125", "ROUTE 127", "ROUTE 127", "ROUTE 129", "ROUTE 129",
}

local failed = 0
for loc = 1, 16 do
  Flags.setVar(session.store, nil, VAR, loc)
  local ctx = { store = session.store, stringVars = { "", "", "" } }
  local ok, _, value = pcall(Natives.special, ctx, SPECIAL, {})
  local got = ctx.stringVars[1]
  local wantType = loc >= 9 and 1 or 0
  if ok and got == want[loc] and value == wantType then
    print(("[ok] location %d -> %s, type %d"):format(loc, got, value))
  else
    failed = failed + 1
    print(("[FAIL] location %d -> %s, type %s (want %s, %d)"):format(loc, tostring(got), tostring(value), want[loc], wantType))
  end
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
os.exit(0)
