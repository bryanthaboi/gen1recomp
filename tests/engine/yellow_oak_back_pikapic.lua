-- Yellow's two extra pic rips and the plumbing that reaches for them.
--
-- #557: LoadPlayerBackPic (pokeyellow engine/battle/core.asm:6384-6391)
-- loads OldManPicBack for BATTLE_TYPE_OLD_MAN but ProfOakPicBack for
-- BATTLE_TYPE_PIKACHU, the Pallet Town catch scene, and DisplayBattleMenu
-- splits the displayed thrower name on the same wBattleType.  The port
-- carries that split as makeOldManDemo's kind argument.
--
-- #561: TalkToPikachu's framed portrait draws the chosen PikaPicAnimScript's
-- own base frame (data/pikachu/pikachu_pic_animation.asm), not the battle
-- front pic that stood in for all of them.
--
-- Both rips are gated on manifest symbols, so tools/rom_manifest_yellow.json
-- is as much a part of these fixes as the Lua is: without the symbol the
-- extractor writes nothing, the runtime existence check falls back, and the
-- screen looks exactly like the bug report.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local BattleState = require("src.battle.BattleState")
local FieldDefaults = require("src.world.FieldDefaults")
local Sprites = require("src.pokemon.Sprites")

local PROF_BACK = "assets/generated/battle/profoakb.png"
local OLDMAN_BACK = "assets/generated/battle/oldmanb.png"
local RED_BACK = "assets/generated/battle/redb.png"

local function readFile(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local text = handle:read("*a")
  handle:close()
  return text
end

-- ---------------------------------------------------------------------
-- #557: the back pic keys and the wBattleType split
-- ---------------------------------------------------------------------

T.eq(FieldDefaults.fieldValue(nil, "playerPics", "oakBack"), PROF_BACK,
  "playerPics carries a third back pic for the PROF.OAK demo")
T.eq(FieldDefaults.fieldValue(nil, "playerPics", "demoBack"), OLDMAN_BACK,
  "the old man's back pic is untouched")

-- The love stub's filesystem is a table of written files, so writing the
-- path IS "this cache was imported after the rip landed".
love.filesystem.write(PROF_BACK, "png")
T.eq(Sprites.playerPath(nil, "back", { demo = true, oakDemo = true }),
  PROF_BACK, "the Pallet catch demo fights behind Oak's own back pic")
T.eq(Sprites.playerPath(nil, "back", { demo = true }), OLDMAN_BACK,
  "the Route 5 catch tutorial still gets the old man")
T.eq(Sprites.playerPath(nil, "back", {}), RED_BACK,
  "an ordinary battle still gets the player")

love.filesystem.remove(PROF_BACK)
T.eq(Sprites.playerPath(nil, "back", { demo = true, oakDemo = true }),
  OLDMAN_BACK,
  "a cache built before the rip falls back to the old man, not a missing file")

-- makeOldManDemo only fills fields when a player battler already exists, so
-- a stub with one stays clear of Pokemon.new and the fixture dataset.
local names = { text = {
  ["DisplayBattleMenu.oldManName"] = "OLD MAN",
  ["DisplayBattleMenu.profOakName"] = "PROF.OAK",
} }
local oak = { player = true, data = names }
BattleState.makeOldManDemo(oak, "oak")
T.eq(oak.demoName, "PROF.OAK", "the Yellow demo names PROF.OAK as the thrower")
T.eq(oak.oakDemo, true, "and asks for his back pic")

local oldMan = { player = true, data = names }
BattleState.makeOldManDemo(oldMan)
T.eq(oldMan.demoName, "OLD MAN", "the unnamed demo is still the old man")
T.eq(oldMan.oakDemo, false, "and does not reach for Oak's pic")

-- ---------------------------------------------------------------------
-- the symbol tables the two rips are gated on
-- ---------------------------------------------------------------------

local extractor = readFile("src/import/RomExtractor.lua")
T.check(extractor ~= nil, "src/import/RomExtractor.lua is readable")
extractor = extractor or ""

local yellowManifest = readFile("tools/rom_manifest_yellow.json")
T.check(yellowManifest ~= nil, "tools/rom_manifest_yellow.json is readable")
yellowManifest = yellowManifest or ""

local generator = readFile("tools/make_yellow_manifest.py")
T.check(generator ~= nil, "tools/make_yellow_manifest.py is readable")
generator = generator or ""

-- Every symbol below is real in pokeyellow.sym; what decides whether the
-- extractor can see it is whether the generator injects it.  Red never
-- referenced any of them, so make_yellow_manifest's Red-name remap cannot
-- pick them up on its own -- they have to be listed in YELLOW_EXTRA_SYMBOLS.
-- One line per group rather than per label: a missing symbol list reads as
-- one fault to fix, not fifty-odd.
local function missingFrom(text, labels)
  local missing = {}
  for _, label in ipairs(labels) do
    if not text:find('"' .. label .. '"', 1, true) then
      missing[#missing + 1] = label
    end
  end
  return missing
end

local function requireSymbols(labels, why)
  local gone = missingFrom(yellowManifest, labels)
  T.check(#gone == 0, why .. ": rom_manifest_yellow.json is missing "
    .. (#gone == 0 and "nothing" or table.concat(gone, " ")))
  gone = missingFrom(generator, labels)
  T.check(#gone == 0, why .. ": make_yellow_manifest.py never asks for "
    .. (#gone == 0 and "nothing" or table.concat(gone, " "))
    .. " (add them to YELLOW_EXTRA_SYMBOLS)")
end

T.check(extractor:find('self.symbols["ProfOakPicBack"]', 1, true) ~= nil,
  "the extractor gates Oak's back pic on the ProfOakPicBack symbol")
requireSymbols({ "ProfOakPicBack" }, "#557")
requireSymbols({ "DisplayBattleMenu.profOakName" }, "#557 thrower name")
T.check(yellowManifest:find('"DisplayBattleMenu.oldManName"', 1, true) ~= nil,
  "rom_manifest_yellow.json carries DisplayBattleMenu.oldManName")

local PikachuPicExtractor = require("src.import.PikachuPicExtractor")
local pikapic = PikachuPicExtractor.symbolNames()
T.eq(#pikapic, 12, "PikachuPicExtractor reads twelve pikachu tables")
requireSymbols(pikapic, "#561")

-- Red and Blue have neither pic, so neither manifest may grow one: a stray
-- entry there would rip Yellow art out of the wrong ROM.
for _, path in ipairs({ "tools/rom_manifest.json", "tools/rom_manifest_blue.json" }) do
  local text = readFile(path)
  T.check(text ~= nil, path .. " is readable")
  T.check(text == nil or text:find("ProfOakPicBack", 1, true) == nil,
    path .. " has no ProfOakPicBack, matching pokered")
end

T.finish("yellow oak back pic and pikapic bases")
