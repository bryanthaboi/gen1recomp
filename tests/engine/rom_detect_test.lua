package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local RomDetect = require("src.import.RomDetect")
local GameVersion = require("src.core.GameVersion")

local MIB = 1024 * 1024

local SHA = {
  red = "ea9bcae617fdf159b045185467ae58b2e4a48b9a",
  blue = "d7037c83e1ae5b39bde3c30787637ba1d4c48ce2",
  yellow = "cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1",
  gold = "d8b8a3600a465308c9953dfa04f0081c05bdcb94",
  silver = "49b163f7e57702bc939d642a18f591de55d92dae",
  crystal = "f4cd194bdee0d04ca4eac29e09b8e4e9d818c133",
  crystal11 = "f2f52230b536214ef7c9924f483392993e226cfb",
  firered = "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc",
  emerald = "f3ae088181bf583e55daf962a92bb46f4f1d07b7",
}
local UNKNOWN = "0000000000000000000000000000000000000000"

-- 1. Size narrows the field --------------------------------------------------

local function names(list) return table.concat(list, ",") end

T.eq(names(RomDetect.versionsForSize(MIB)), "red,blue,yellow",
  "1 MiB is only the three Gen 1 carts")
T.eq(names(RomDetect.versionsForSize(2 * MIB)), "gold,silver,crystal",
  "2 MiB is only the three Gen 2 carts")
T.eq(names(RomDetect.versionsForSize(16 * MIB)),
  "firered,leafgreen,ruby,sapphire,emerald",
  "16 MiB is only the five GBA games")
T.eq(#RomDetect.versionsForSize(3 * MIB), 0, "3 MiB is no cart at all")
T.eq(#RomDetect.versionsForSize(nil), 0, "a missing size is no cart at all")
T.eq(#RomDetect.versionsForSize("1048576"), 0, "a string size is not a size")

-- Every cart is reachable through its own size, so the gate hides nothing.
local rows = 0
for _, version in ipairs(GameVersion.ORDER) do
  local size = GameVersion.info(version).romSize
  local found = false
  for _, candidate in ipairs(RomDetect.versionsForSize(size)) do
    if candidate == version then found = true end
  end
  T.check(found, version .. " is reachable through its own size")
  rows = rows + #GameVersion.revisions(version)
end
T.eq(rows, 18, "the README table still has 18 accepted revisions")

-- 2. SHA-1 decides -----------------------------------------------------------

local function identify(hash, size, extra)
  local entry = { size = size, data = string.rep("\0", size or 0), sha1 = hash }
  for key, value in pairs(extra or {}) do entry[key] = value end
  return RomDetect.identify(entry)
end

local hit = identify(SHA.red, MIB)
T.eq(hit.version, "red", "the Red hash resolves to Red")
T.eq(hit.revision, nil, "Red has a single revision, so there is no label")

hit = identify(SHA.crystal11, 2 * MIB)
T.eq(hit.version, "crystal", "the Crystal rev 1.1 hash resolves to Crystal")
T.eq(hit.revision, "1.1", "and the revision label is carried through")

hit = identify(SHA.emerald, 16 * MIB)
T.eq(hit.version, "emerald", "a 16 MiB GBA dump resolves through its own size")

-- The name is not an input: Blue bytes are Blue whatever the file is called.
hit = identify(SHA.blue, MIB, { name = "totally unrelated name.gb" })
T.eq(hit.version, "blue", "the name has no say in the result")

hit = identify(SHA.blue, MIB, { name = "Pokemon - Red Version (USA, Europe).gb" })
T.eq(hit.version, "blue", "a Red filename over Blue bytes still resolves to Blue")

-- 3. What a hash alone cannot do ---------------------------------------------

local miss = identify(UNKNOWN, MIB)
T.eq(miss.reject, "unknown", "an unrecognised hash is not guessed at")
T.eq(names(miss.versions or {}), "red,blue,yellow",
  "and the rejection names every cart that size could have been")

miss = identify(SHA.red, 3 * MIB)
T.eq(miss.reject, "size", "an impossible size is rejected before any hash work")

-- A Gold hash cannot belong to a 1 MiB file.
miss = identify(SHA.gold, MIB)
T.eq(miss.reject, "unknown", "a hash the size contradicts is not trusted")

miss = identify(nil, MIB)
T.eq(miss.reject, "unknown", "a caller with no hash gets no answer")

-- 4. Already-satisfied versions ----------------------------------------------

local unresolved = { blue = true, yellow = true }
local already = RomDetect.identify(
  { size = MIB, data = string.rep("\0", MIB), sha1 = SHA.red },
  { unresolved = unresolved })
T.eq(already.reject, "already", "a cart that is not needed is not offered")
T.eq(already.version, "red", "and the rejection still says which cart it was")

local wanted = RomDetect.identify(
  { size = MIB, data = string.rep("\0", MIB), sha1 = SHA.blue },
  { unresolved = unresolved })
T.eq(wanted.version, "blue", "a cart that is still needed is offered")

-- 5. Hash as a function, and revisionFor --------------------------------------

local calls = 0
local hashed = RomDetect.identify({
  size = MIB, data = string.rep("\0", MIB),
  sha1 = function(data) calls = calls + 1 return SHA.yellow end,
})
T.eq(hashed.version, "yellow", "a hash function is called with the bytes")
T.eq(calls, 1, "exactly once per candidate")

T.eq(RomDetect.revisionFor("crystal", SHA.crystal), "1.0",
  "revisionFor reads the first Crystal revision")
T.eq(RomDetect.revisionFor("crystal", SHA.crystal11), "1.1",
  "revisionFor reads the second Crystal revision")
T.eq(RomDetect.revisionFor("red", UNKNOWN), nil,
  "revisionFor answers nil for a hash the cart does not have")

T.finish("rom detect")
