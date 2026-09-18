-- The parity-guarantee meta-test (21-testing-and-ci "parity gate for every
-- extension point"; 26 M14 "the suite tests itself").
--
-- The rule D14 states is that every extension point ships three artifacts
-- in the same change: a unit test through the public mod API, a no-mod
-- parity test, and docs.  This file is what makes that a gate instead of a
-- convention.
--
-- Two directions are enforced:
--
--   parity  -- structural.  gate_hooks/gate_events/gate_registries each
--              walk the live catalog rather than a hand-kept list, so
--              every seam is parity-gated the moment its call site exists.
--              This file asserts those gates really do iterate the
--              catalog, which is the property that makes the coverage
--              automatic.
--
--   unit    -- a ratchet.  A seam is "covered" when some test names it.
--              Seams that predate this gate are listed in DEBT below with
--              the milestone that owes them.  A seam missing from both the
--              corpus and DEBT fails -- that is the gate on new work.  A
--              seam in DEBT that has since been covered ALSO fails, so the
--              ledger cannot rot into a permanent excuse; it only shrinks.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Catalog = T.catalog

-- ------- parity side

local PARITY_GATES = {
  { kind = "hooks", file = "tests/engine/gate_hooks.lua", accessor = "Catalog.hooks()" },
  { kind = "events", file = "tests/engine/gate_events.lua", accessor = "Catalog.events()" },
  { kind = "registries", file = "tests/engine/gate_registries.lua",
    accessor = "T.catalog.registries()" },
}

local function slurp(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local body = handle:read("*a")
  handle:close()
  return body
end

for _, gate in ipairs(PARITY_GATES) do
  local body = slurp(gate.file)
  T.check(body ~= nil, "a no-mod parity gate exists for " .. gate.kind .. ": " .. gate.file)
  if body then
    -- the gate must derive its subjects from the catalog; a gate that
    -- inlined its own list would silently stop covering new seams
    T.check(body:find(gate.accessor, 1, true) ~= nil,
      ("the %s gate walks the live catalog (%s)"):format(gate.kind, gate.accessor))
    T.check(body:find("T.finish", 1, true) ~= nil,
      "the " .. gate.kind .. " gate reports through the shared harness")
  end
end

-- ------- unit side

-- every file that can hold a seam's unit test: the mod-API suites, the
-- engine tier, the SDK cases, and any tests a shipped mod carries
local function testCorpus()
  local files, bodies = {}, {}
  local FsIo = require("tests.fs_io")
  local function addLuaFrom(dir)
    for _, name in ipairs(FsIo.listDir(dir)) do
      if name:match("%.lua$") then files[#files + 1] = dir .. "/" .. name end
    end
  end
  addLuaFrom("tests")
  addLuaFrom("tests/engine")
  addLuaFrom("tests/modkit/cases")
  for _, mod in ipairs(FsIo.listDir("mods")) do
    if not mod:find(".", 1, true) then addLuaFrom("mods/" .. mod .. "/tests") end
  end
  for _, path in ipairs(files) do
    bodies[path] = slurp(path) or ""
  end
  return bodies
end

local corpus = testCorpus()
local corpusCount = 0
for _ in pairs(corpus) do corpusCount = corpusCount + 1 end
T.check(corpusCount > 0, "the test corpus is non-empty")

-- a seam is covered when a test names it in quotes -- registrations and
-- subscriptions are written too many ways (literal, table-driven loop,
-- built-up string) for a syntactic match to be reliable, but a test that
-- exercises a seam always names it
local function coveredBy(name)
  local needle = '"' .. name .. '"'
  for path, body in pairs(corpus) do
    if body:find(needle, 1, true) then return path end
  end
  return nil
end

-- Coverage debt inherited from the milestones that introduced these seams
-- (M14 adds the gate; it does not retro-fit other milestones' unit tests).
-- Removing a name from this list is the only way to close its entry, and
-- the staleness check below forces that the moment a test lands.
--
-- The Gen 2 tier drained most of this ledger: tests/engine/gate_gen2_mod_api.lua
-- names each seam Gold raises and holds it to having a call site in BOTH
-- generations under the one shared name, which is a test that fails if the
-- seam is deleted or renamed.  It is not a payload case, so a per-seam case
-- through the public mod API is still worth writing for those names -- it is
-- simply no longer owed as debt, because the ledger's rule is that an entry
-- closes the moment any test names the seam.
local DEBT = {
  -- registry:link_fields closed the same way: the Gen 2 gate names it in the
  -- gated list, because link play is Gen 1 only and Gold has nowhere to put a
  -- link field.  Still not a payload case, still worth one.
  --
  -- hook:render.zones was the last M9 entry and closed when Gold grew its own
  -- zone pass: src/core/Game2.lua:blitZones raises the hook with the same rect
  -- list shape src/render/Renderer.lua does, so gate_gen2_mod_api names it in
  -- the shared-hook list and the ledger's rule ("an entry closes the moment
  -- any test names the seam") retired it.

  ["event:link.connected"] = "M12",
  ["event:link.ended"] = "M12",
  ["event:trade.completed"] = "M12",
}

local seen = {}

local function requireUnitTest(kind, name)
  local key = kind .. ":" .. name
  seen[key] = true
  local where = coveredBy(name)
  if DEBT[key] then
    -- the ratchet: a debt entry that is now covered must be deleted, or
    -- the ledger drifts into fiction
    T.check(where == nil,
      ("%s is covered by %s -- remove the DEBT entry %s (owed by %s)")
        :format(key, tostring(where), key, DEBT[key]))
    return
  end
  T.check(where ~= nil,
    ("%s has no unit test naming it through the public mod API " ..
     "(add one, or add a DEBT entry saying which milestone owes it)"):format(key))
end

for _, name in ipairs(Catalog.registries()) do requireUnitTest("registry", name) end
for _, name in ipairs(Catalog.hooks()) do requireUnitTest("hook", name) end
for _, name in ipairs(Catalog.events()) do
  if not Catalog.isModEvent(name) then requireUnitTest("event", name) end
end

-- a DEBT key for a seam that no longer exists is dead weight; drop it with
-- the seam so the ledger stays a description of the present
for key, owed in pairs(DEBT) do
  T.check(seen[key],
    ("DEBT lists %s (owed by %s) but no such seam is in the catalog -- remove it")
      :format(key, owed))
end

-- ------- docs side

-- the third artifact.  The generated reference is what keeps registry docs
-- from drifting, so assert the generator exists and covers the catalog
-- rather than diffing prose.
do
  local generator = slurp("tools/gen_registry_docs.lua")
  T.check(generator ~= nil, "the registry doc generator exists")
  if generator then
    T.check(generator:find("REGISTRIES", 1, true) ~= nil,
      "the doc generator renders from Schemas.REGISTRIES, not a hand-kept list")
  end
end

T.finish("gate_meta_coverage")
