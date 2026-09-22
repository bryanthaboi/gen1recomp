package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local Schema = require("src.core.game3.save_schema_firered")
local Storage = require("src.core.game3.storage")

print("[test] 1. toSaveTable never writes the legacy pc keys (V10 premise)")
local out = Schema.toSaveTable(Schema.newGame())
check(type(out) == "table", "toSaveTable returns a table")
check(out.pc == nil, "no save.pc key is written")
check(out.pcItems == nil, "no save.pcItems key is written")
check(out.pc_items == nil, "no save.pc_items key is written")

print("[test] 2. legacy save.pc {items=..., mons=...} lands in the modern blob")
local s1 = Schema.fromSaveTable({
  pc = { items = { { id = 4, qty = 5 } }, mons = { { species = 1, level = 5 } } },
})
check(type(s1.storage) == "table", "session.storage built")
local it = s1.storage.items and s1.storage.items[1]
check(it and it.id == 4 and it.qty == 5, "legacy pc.items copied into storage.items")
check(Storage.countTotalMons(s1.storage) >= 1, "legacy pc.mons copied into the boxes")

print("[test] 3. legacy pcItems id -> count map")
local s2 = Schema.fromSaveTable({ pcItems = { [4] = 7 } })
local it2 = s2.storage.items and s2.storage.items[1]
check(it2 and it2.id == 4 and it2.qty == 7, "save.pcItems numeric map copied")

print("[test] 4. pc_items alias reaches the same branch")
local s3 = Schema.fromSaveTable({ pc_items = { [4] = 9 } })
local it3 = s3.storage.items and s3.storage.items[1]
check(it3 and it3.id == 4 and it3.qty == 9, "save.pc_items alias copied")

print("[test] 5. modern storage blob wins — legacy pcItems ignored")
local modern = Storage.new()
modern.items = { { id = 200, qty = 2 } }
local s4 = Schema.fromSaveTable({ storage = Storage.serialize(modern), pcItems = { [4] = 7 } })
local has4, has200 = false, false
for _, e in ipairs(s4.storage.items or {}) do
  if e.id == 4 then has4 = true end
  if e.id == 200 then has200 = true end
end
check(not has4, "pcItems ignored when a modern storage blob exists")
check(has200, "modern blob items preserved")

print("[test] 6. F3: engine/version/generation round-trip")
local t = Schema.toSaveTable(Schema.newGame())
check(t.engine == "game3", "toSaveTable writes engine")
check(t.generation == 3, "toSaveTable writes generation")
local r = Schema.fromSaveTable(t)
check(r.engine == "game3", "fromSaveTable reads engine back")
check(r.generation == 3, "fromSaveTable reads generation back")
check(r.version == t.version, "version round-trips")
local old = Schema.fromSaveTable({ version = t.version })
check(old.generation == 3, "older saves default generation to 3 (newGame parity)")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
os.exit(0)
