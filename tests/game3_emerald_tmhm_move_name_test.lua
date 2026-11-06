#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local CacheBlob = require("src.import.CacheBlob")

local function emeraldRoot()
  local home, identity = os.getenv("HOME"), os.getenv("POKEPORT_IDENTITY")
  if not (home and identity and identity ~= "") then return nil end
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE", home .. "/.local/share/love" }) do
    local root = base .. "/" .. identity .. "/emerald/"
    local f = io.open(root .. "data/generated/gba/meta.json", "rb")
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
  for _, path in ipairs({ ROOT .. rel, ROOT .. "data/generated/gba/" .. rel }) do
    local f = io.open(path, "rb")
    if f then
      local s = CacheBlob.decode(rel, f:read("*a"))
      f:close()
      return s
    end
  end
  return nil
end

_G.love = { filesystem = {
  getInfo = function(p) if readFile(p) then return {} end end,
  load = function(p) local s = readFile(p) return s and loadstring(s, "@" .. p) end,
  read = function(p) return readFile(p) end,
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
local SPECIAL = C.specials.byName.BufferTMHMMoveName

local failed = 0
local function check(label, cond, detail)
  if cond then
    print("[ok] " .. label)
  else
    failed = failed + 1
    print("[FAIL] " .. label .. " " .. tostring(detail))
  end
end

-- pokeemerald/src/field_specials.c:1638
local cases = {
  { item = C:require("items", "ITEM_TM48"), want = "SKILL SWAP" },
  { item = C:require("items", "ITEM_TM37"), want = "SANDSTORM" },
  { item = C:require("items", "ITEM_TM01"), want = "FOCUS PUNCH" },
  { item = C:require("items", "ITEM_HM08"), want = "DIVE" },
}
for _, case in ipairs(cases) do
  local ctx = { store = session.store, specialVars = {}, stringVars = { "TM_NAME", "STALE", "" } }
  Flags.setVar(session.store, ctx, 0x8004, case.item)
  local ok, _, value = pcall(Natives.special, ctx, SPECIAL, {})
  check(("item %d writes STR_VAR_2 = %s"):format(case.item, case.want),
    ok and value == 1 and ctx.stringVars[2] == case.want,
    ("ok=%s value=%s var2=%s"):format(tostring(ok), tostring(value), tostring(ctx.stringVars[2])))
  check(("item %d leaves STR_VAR_1"):format(case.item), ctx.stringVars[1] == "TM_NAME", tostring(ctx.stringVars[1]))
end

local ctx = { store = session.store, specialVars = {}, stringVars = { "A", "B", "C" } }
Flags.setVar(session.store, ctx, 0x8004, C:require("items", "ITEM_POTION"))
local ok, _, value = pcall(Natives.special, ctx, SPECIAL, {})
check("non-TM item returns FALSE and leaves vars", ok and value == 0
  and ctx.stringVars[1] == "A" and ctx.stringVars[2] == "B" and ctx.stringVars[3] == "C",
  ("ok=%s value=%s"):format(tostring(ok), tostring(value)))

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
os.exit(0)
