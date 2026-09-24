package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
if not _G.love then _G.love = require("tests.love_stub") end

local Cache = require("tests.game3_cache")
local frRoot = Cache.mount("meta.json")
if not frRoot then
  print("[skip] online_fingerprint3: " .. tostring(Cache.reason))
  os.exit(0)
end

local Fingerprint = require("src.link.Fingerprint")
local Handshake = require("src.link.Handshake")

local function reader(root)
  return function(rel)
    local f = io.open(root .. "/" .. rel:gsub("^data/generated/gba/", ""), "rb")
    if not f then return nil end
    local body = f:read("*a")
    f:close()
    return body
  end
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function versionRoot(identity, version)
  local home = os.getenv("HOME") or ""
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE/",
                          home .. "/.local/share/love/" }) do
    local root = base .. identity .. "/" .. version .. "/data/generated/gba"
    if exists(root .. "/meta.json") then return root end
  end
  return nil
end

local function data3(root)
  return { generation = 3, gen3Inputs = Fingerprint.gen3Inputs(reader(root)) }
end

T.eq(Fingerprint.generationOf({ generation = 3 }), 3, "a dataset that says Gen 3 is Gen 3")
T.eq(Fingerprint.generationOf({ type_chart = { generation = 2 } }), 2, "Gold still reads as Gen 2")
T.eq(Fingerprint.generationOf({}), 1, "an unknown dataset still reads as Gen 1")

local fr = data3(frRoot)
local fpFR = Fingerprint.compute(fr, {}, 3)
T.check(type(fpFR) == "string" and #fpFR == 16, "a Gen 3 digest is computed")
T.eq(Fingerprint.compute(data3(frRoot), {}), fpFR,
  "two reads of the same cache hash the same (generation from the data)")
T.check(Fingerprint.surface(fr, {}, 3):sub(1, 6) == "[gen3]", "the surface opens with [gen3]")
T.check(Fingerprint.compute({ generation = 1, gen3Inputs = fr.gen3Inputs }, {}, 1) ~= fpFR,
  "a Gen 1 surface over the same tables is a different digest")

T.check(Fingerprint.compute(data3(frRoot), { { id = "rebalance", version = "1.0" } }, 3) ~= fpFR,
  "a link-affecting mod moves the digest")
T.eq(Fingerprint.compute(data3(frRoot),
  { { id = "espanol", version = "1.0", affectsLink = false } }, 3), fpFR,
  "a mod that declares no link effect does not")

local tweaked = data3(frRoot)
tweaked.gen3Inputs.stats[25].atk = tweaked.gen3Inputs.stats[25].atk + 1
T.check(Fingerprint.compute(tweaked, {}, 3) ~= fpFR, "one base stat moves the digest")
local moved = data3(frRoot)
moved.gen3Inputs.moves[85].power = 91
T.check(Fingerprint.compute(moved, {}, 3) ~= fpFR, "one move's power moves the digest")
local held = data3(frRoot)
held.gen3Inputs.items[200].holdEffectParam = 99
T.check(Fingerprint.compute(held, {}, 3) ~= fpFR, "one hold effect param moves the digest")
local nat = data3(frRoot)
nat.gen3Inputs.natures[2][1] = 1
T.check(Fingerprint.compute(nat, {}, 3) ~= fpFR, "the nature table is hashed")
local chart = data3(frRoot)
chart.gen3Inputs.typeChart[3] = 10
T.check(Fingerprint.compute(chart, {}, 3) ~= fpFR, "the type chart is hashed")
local deoxys = data3(frRoot)
deoxys.gen3Inputs.stats[410].atk = 1
T.eq(Fingerprint.compute(deoxys, {}, 3), fpFR, "Deoxys' per-cart form stats are not surface")

local ok, err = pcall(Fingerprint.gen3Inputs, function() return nil end)
T.check(not ok and tostring(err):find("pokemon/stats.lua", 1, true) ~= nil,
  "a cache missing a surface file is an error, not a guess")

local live = { generation = 3 }
T.eq(Fingerprint.compute(live, {}, 3), fpFR,
  "a live dataset with no inputs reads the mounted cache and agrees")

local game3 = { data = { gen3Pokemon = require("src.core.game3.pokemon") },
                save = { name = "RED", options = {} } }
local helloLive = Handshake.hello(game3)
T.eq(helloLive.generation, 3, "a Game3-shaped object hellos as Gen 3")
T.eq(helloLive.name, "RED", "with the save's trainer name")
T.eq(helloLive.fingerprint, fpFR, "and the Gen 3 digest")
T.eq(Handshake.generation({ generation = 3 }), 3, "a game's own generation wins")

local lgIdentity = os.getenv("POKEPORT_IDENTITY_LG")
local lgRoot = lgIdentity and versionRoot(lgIdentity, "leafgreen")
if not lgRoot then
  print("[skip] FR==LG half: set POKEPORT_IDENTITY_LG to a LeafGreen identity")
else
  local lg = data3(lgRoot)
  T.check(lg.gen3Inputs.stats[410].atk ~= fr.gen3Inputs.stats[410].atk,
    "the two carts' Deoxys forms really differ")
  local fpLG = Fingerprint.compute(lg, {}, 3)
  T.eq(fpLG, fpFR, "FireRed and LeafGreen hash equal")
  local helloFR = Handshake.hello({ data = data3(frRoot), save = { player = { name = "RED" } } })
  local helloLG = Handshake.hello({ data = data3(lgRoot), save = { player = { name = "LEAF" } } })
  T.eq(helloFR.generation, 3, "the hello says Gen 3")
  T.eq(helloFR.fingerprint, fpFR, "and carries the real Gen 3 digest")
  T.eq((Handshake.checkCompat(helloFR, helloLG)), "full", "FireRed meets LeafGreen as full")
end

local frIdentity2 = os.getenv("POKEPORT_IDENTITY_FR2")
local frRoot2 = frIdentity2 and versionRoot(frIdentity2, "firered")
if not frRoot2 then
  print("[skip] second-identity half: set POKEPORT_IDENTITY_FR2 to another FireRed identity")
else
  T.eq(Fingerprint.compute(data3(frRoot2), {}, 3), fpFR,
    "the same cache in another identity hashes the same")
end

T.finish()
