-- Yellow's Jessie & James battle behind their own pic while keeping the
-- ROCKET class and the name "ROCKET" (#439).  pokeyellow
-- home/trainers2.asm:36-50 IsFightingJessieJames swaps wTrainerPicPointer
-- for JessieJamesPic when wTrainerClass is ROCKET and wTrainerNo >= $2a
-- (parties 42-45), and GetTrainerName right below it is untouched, so only
-- the pic changes.  Red has no such symbol, so the swap must stay Yellow's.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local BattleState = require("src.battle.BattleState")

local CLASS_PIC = "assets/generated/battle/trainers/rocket.png"
local DUO_PIC = "assets/generated/battle/trainers/jessie_james.png"

-- a Yellow cache extracted after #439: OPP_ROCKET carries both pics
local yellow = { name = "ROCKET", pic = CLASS_PIC, picJessieJames = DUO_PIC }
-- Red/Blue, and any Yellow cache built before #439, carry only the class pic
local grunt = { name = "ROCKET", pic = CLASS_PIC }

for _, party in ipairs({ 42, 43, 44, 45 }) do
  T.eq(BattleState.trainerPicPath(yellow, "OPP_ROCKET", party), DUO_PIC,
    "party " .. party .. " fights behind the duo pic")
end
T.eq(yellow.name, "ROCKET", "the duo keeps the class name")

-- $2a is the first duo party; every grunt below it keeps the class pic
T.eq(BattleState.trainerPicPath(yellow, "OPP_ROCKET", 41), CLASS_PIC,
  "party 41 is still a lone grunt")
T.eq(BattleState.trainerPicPath(yellow, "OPP_ROCKET", 1), CLASS_PIC,
  "the first ROCKET party is still a lone grunt")
T.eq(BattleState.trainerPicPath(yellow, "OPP_ROCKET", nil), CLASS_PIC,
  "an unnumbered ROCKET falls back to party 1")
T.eq(BattleState.trainerPicPath(
       { pic = "assets/generated/battle/trainers/super_nerd.png",
         picJessieJames = DUO_PIC }, "OPP_SUPER_NERD", 42),
  "assets/generated/battle/trainers/super_nerd.png",
  "the class gate holds: only ROCKET swaps")
T.eq(BattleState.trainerPicPath(grunt, "OPP_ROCKET", 42), CLASS_PIC,
  "a cache with no duo pic keeps the grunt instead of a nil pic")

-- The extractor writes jessie_james.png only when the symbol is in the
-- manifest, so the symbol table is the other half of the contract.
local function readFile(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local text = handle:read("*a")
  handle:close()
  return text
end

local yellowManifest = readFile("tools/rom_manifest_yellow.json")
T.check(yellowManifest ~= nil, "tools/rom_manifest_yellow.json is readable")
if yellowManifest then
  local bank, addr = yellowManifest:match(
    '"JessieJamesPic"%s*:%s*%[%s*(%d+)%s*,%s*(%d+)%s*%]')
  T.eq(bank, "19", "JessieJamesPic sits in bank 0x13")
  T.eq(addr, "31873", "JessieJamesPic sits at 0x7c81 in that bank")
end

for _, path in ipairs({ "tools/rom_manifest.json", "tools/rom_manifest_blue.json" }) do
  local text = readFile(path)
  T.check(text ~= nil, path .. " is readable")
  T.check(text == nil or text:find("JessieJamesPic", 1, true) == nil,
    path .. " has no such symbol, matching pokered")
end

-- the manifest is generated, so the generator has to keep asking for it
local gen = readFile("tools/make_yellow_manifest.py")
T.check(gen ~= nil, "tools/make_yellow_manifest.py is readable")
T.check(gen == nil or gen:find('"JessieJamesPic"', 1, true) ~= nil,
  "a regenerated Yellow manifest keeps JessieJamesPic")

T.finish("jessie james pic")
