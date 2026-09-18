#!/usr/bin/env luajit
-- Test for ROM-native battle animation pack and tag sprites.
-- Run: luajit tests/game3_battle_anim_pack_test.lua

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

print("=== 1. Load Extracted Battle Anim Pack ===")
local packPath = (os.getenv("HOME") or ".") .. "/.local/share/love/pokemon-love2d/firered/data/generated/gba/pokemon/battle_anims/pack.lua"
local chunk, err = loadfile(packPath)
check(chunk ~= nil, "pack.lua loads without syntax errors: " .. tostring(err))

local pack = chunk and chunk() or {}
check(type(pack) == "table", "pack is a table")
check(pack.version == 5, "pack version is 5 (ROM-native, indexed sheets)")
check(type(pack.moves) == "table", "pack.moves is a table")
check(type(pack.labels) == "table", "pack.labels is a table")
check(type(pack.tags) == "table", "pack.tags is a table")

print("\n=== 2. Verify Move Scripts ===")
local totalMoves = 0
local totalOps = 0
local opCounts = {}

for id = 0, 354 do
  local script = pack.moves[id]
  if script and #script > 0 then
    totalMoves = totalMoves + 1
    totalOps = totalOps + #script
    for _, op in ipairs(script) do
      local code = op.op or op[1]
      opCounts[code] = (opCounts[code] or 0) + 1
    end
  end
end

check(totalMoves == 355, string.format("All 355 moves decoded (found %d)", totalMoves))
check(totalOps > 1000, string.format("Decoded %d total IR ops across all moves", totalOps))

print("Opcode distribution across moves:")
for code, count in pairs(opCounts) do
  print(string.format("  %-20s: %d", code, count))
end

print("\n=== 3. Verify Specific Move Bytecode Details ===")
-- MOVE_TACKLE = 33
local tackle = pack.moves[33]
check(tackle ~= nil and #tackle > 0, "MOVE_TACKLE (33) exists")
local hasSprite = false
local hasLunge = false
for _, op in ipairs(tackle) do
  if op.op == "createsprite" then
    hasSprite = true
    if op.noGfx then hasLunge = true end
  end
end
check(hasSprite, "Tackle has createsprite op")
check(hasLunge, "Tackle has noGfx (HorizontalLunge) sprite op")

-- MOVE_SLASH = 163
local slash = pack.moves[163]
check(slash ~= nil and #slash > 0, "MOVE_SLASH (163) exists")
local hasSlashTag = false
for _, op in ipairs(slash or {}) do
  if op.op == "createsprite" and op.tag == "SLASH" then
    hasSlashTag = true
  end
end
check(hasSlashTag, "Slash has createsprite with tag=SLASH")

print("\n=== 4. Verify Extracted Tag Sprites ===")
local tagCount = 0
for name, meta in pairs(pack.tags) do
  tagCount = tagCount + 1
  assert(meta.file, "tag " .. name .. " has file field")
  assert(meta.w and meta.w > 0, "tag " .. name .. " has positive w")
  assert(meta.h and meta.h > 0, "tag " .. name .. " has positive h")
end
check(tagCount >= 180, string.format("Extracted %d tag sprite metadata entries", tagCount))

local slashMeta = pack.tags["SLASH"]
check(slashMeta ~= nil, "SLASH tag metadata exists")
if slashMeta then
  check(slashMeta.w == 32, string.format("SLASH width is 32 (got %s)", tostring(slashMeta.w)))
  check(slashMeta.h == 128, string.format("SLASH height is 128 (got %s)", tostring(slashMeta.h)))
end

local impactMeta = pack.tags["IMPACT"]
check(impactMeta ~= nil, "IMPACT tag metadata exists")
if impactMeta then
  check(impactMeta.w == 32, string.format("IMPACT width is 32 (got %s)", tostring(impactMeta.w)))
end

if failed > 0 then
  print(string.format("\n[FAIL] %d tests failed!", failed))
  os.exit(1)
else
  print("\n[ok] All battle anim pack tests passed successfully!")
end
