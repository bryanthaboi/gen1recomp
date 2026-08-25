-- Crystal's player gender: the InitGender screen, the byte it writes, and the
-- eight places that read it back.
--   luajit tests/gen2_crystal_gender_test.lua
--
-- Gold and Silver have no Kris to extract, so every assertion comes in a
-- Crystal half and a Gold half: Gold must still boot straight into Oak with no
-- gender beat in the speech and Chris on the field.
-- The cache half SKIPs when no crystal cache is present.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 crystal gender")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local FieldMoves = require("src.world.gen2.FieldMoves")
local GameVersion = require("src.core.GameVersion")
local GenderSelect = require("src.ui.gen2.GenderSelect")
local NamePick = require("src.ui.gen2.NamePick")
local NamingScreen = require("src.ui.gen2.NamingScreen")
local OakSpeech = require("src.ui.gen2.OakSpeech")
local Pokegear = require("src.ui.gen2.Pokegear")
local Save = require("src.core.gen2.Save")
local Screens = require("src.ui.Screens")
local TrainerCard = require("src.ui.gen2.TrainerCard")

local priorVersion = GameVersion.get()

-- ------------------------------------------------- the two sprite tables

-- data/sprites/player_sprites.asm
eq(FieldMoves.stateSprite("normal", "male"), "SPRITE_CHRIS", "Chris on foot")
eq(FieldMoves.stateSprite("bike", "male"), "SPRITE_CHRIS_BIKE", "Chris biking")
eq(FieldMoves.stateSprite("normal", "female"), "SPRITE_KRIS", "Kris on foot")
eq(FieldMoves.stateSprite("bike", "female"), "SPRITE_KRIS_BIKE", "Kris biking")
eq(FieldMoves.stateSprite("surf", "female"), "SPRITE_SURF",
  "both share the Lapras")
eq(FieldMoves.stateSprite("surf_pika", "female"), "SPRITE_SURFING_PIKACHU",
  "and the surfing PIKACHU")
eq(FieldMoves.stateSprite("normal", nil), "SPRITE_CHRIS",
  "no recorded gender is PLAYERGENDER_MALE")
eq(FieldMoves.stateSprite("skate", "female"), "SPRITE_KRIS",
  "a state with no row falls back to PLAYER_NORMAL's")
eq(FieldMoves.playerSprite("female"), "SPRITE_KRIS", "playerSprite is the same")
check(FieldMoves.isFemale("female"), "female reads as PLAYERGENDER_FEMALE_F")
check(not FieldMoves.isFemale("male"), "male does not")
check(not FieldMoves.isFemale(nil), "and neither does an absent byte")

check(FieldMoves.hasGenderChoice({ SPRITE_KRIS = {} }),
  "a cache with SPRITE_KRIS offers the choice")
check(not FieldMoves.hasGenderChoice({ SPRITE_CHRIS = {} }),
  "a Gold cache does not")
check(not FieldMoves.hasGenderChoice(nil), "and neither does no cache at all")

-- ------------------------------------------------- the save field (CT-5)

eq(Save.defaultPlayerName("crystal", "male"), "CHRIS", "MalePlayerNameArray[0]")
eq(Save.defaultPlayerName("crystal", "female"), "KRIS",
  "FemalePlayerNameArray[0]")
eq(Save.defaultPlayerName("gold", "female"), "GOLD",
  "Gold has no female array to fall into")
eq(Save.defaultPlayerName("silver", "female"), "SILVER", "nor does Silver")
eq(Save.defaultPlayerName("crystal"), "CHRIS", "and no gender is Chris")

check(Save.isFemale({ player = { gender = "female" } }), "isFemale on a save")
check(not Save.isFemale({ player = { gender = "male" } }), "and not on Chris")
check(not Save.isFemale({}), "nor on a save with no player block")

GameVersion.set("crystal")
local kris = Save.newGame({ gender = "female" })
eq(kris.player.gender, "female", "newGame records the answer")
eq(kris.player.name, "KRIS", "and lays down .Kris as the default name")
local chris = Save.newGame({})
eq(chris.player.gender, "male", "InitCrystalData zeroes the byte")
eq(chris.player.name, "CHRIS", "so a fresh save is Chris")
eq(Save.newGame({ gender = "female", playerName = "ZZ" }).player.name, "ZZ",
  "an explicit name still wins")

local normalized = Save.normalize({ version = "crystal",
  player = { gender = "female" } })
eq(normalized.player.name, "KRIS", "normalize fills the gendered default")
eq(Save.normalize({ version = "crystal", player = {} }).player.name, "CHRIS",
  "and the male one with no byte")

-- ------------------------------------------------- the name presets

GameVersion.set("crystal")
eq(NamePick.presetsFor("male")[1], "CHRIS", "ChrisNameMenuHeader row 1")
eq(NamePick.presetsFor("male")[4], "JON", "and row 4")
eq(NamePick.presetsFor("female")[1], "KRIS", "KrisNameMenuHeader row 1")
eq(NamePick.presetsFor("female")[4], "JODI", "and row 4")
eq(NamePick.presetsFor()[1], "CHRIS", "no gender is the male header")
GameVersion.set("gold")
eq(NamePick.presetsFor("female")[1], "GOLD",
  "Gold keeps PlayerNameArray whatever is asked for")
GameVersion.set("silver")
eq(NamePick.presetsFor("female")[1], "SILVER", "and so does Silver")
GameVersion.set("crystal")

eq(NamingScreen.playerSprite("female"), "SPRITE_KRIS",
  "GetPlayerIcon's female sheet")
eq(NamingScreen.playerSprite("male"), "SPRITE_CHRIS", "and its male one")

-- ------------------------------------------------- the screen itself

check(Screens.GEN2_IDS ~= nil, "the registry lists the Gen 2 screens")
local registered = {}
for _, id in ipairs(Screens.GEN2_IDS) do registered[id] = true end
check(registered.Gen2GenderSelect, "Gen2GenderSelect has an id")
eq(Screens.get({ data = {} }, "Gen2GenderSelect"), GenderSelect,
  "and resolves to the builtin")

eq(GenderSelect.OPTIONS[1].label, "Boy", ".MenuData item 1")
eq(GenderSelect.OPTIONS[1].gender, "male", "writes wPlayerGender 0")
eq(GenderSelect.OPTIONS[2].label, "Girl", ".MenuData item 2")
eq(GenderSelect.OPTIONS[2].gender, "female", "writes wPlayerGender 1")

-- A joypad that answers one press then goes quiet, the way the harness fakes
-- input for every other screen suite here.
local function fakeInput(button)
  local pressed = button
  return {
    wasPressed = function(_, name)
      if pressed and name == pressed then
        pressed = nil
        return true
      end
      return false
    end,
  }
end

local function screenGame(save, button)
  return { save = save, data = {}, input = fakeInput(button) }
end

local save = Save.newGame({})
local answered
local game = screenGame(save, "a")
local screen = GenderSelect.new(game, { onDone = function(g) answered = g end })
eq(screen.cursor, 1, "`db 1 ; default option` opens on Boy")
screen:update(0)
eq(save.player.gender, "male", "A on Boy writes PLAYERGENDER_MALE")
eq(answered, nil, "and the DelayFrames 10 has not run out yet")
for _ = 1, 10 do screen:update(0) end
eq(answered, "male", "onDone fires once the ten frames are gone")

save = Save.newGame({})
game = screenGame(save, "down")
screen = GenderSelect.new(game, { onDone = function() end })
screen:update(0)
eq(screen.cursor, 2, "down walks to Girl")
game.input = fakeInput("down")
screen:update(0)
eq(screen.cursor, 1, "STATICMENU_WRAP wraps at the bottom")
game.input = fakeInput("up")
screen:update(0)
eq(screen.cursor, 2, "and at the top")
game.input = fakeInput("b")
screen:update(0)
eq(save.player.gender, "male", "STATICMENU_DISABLE_B: B answers nothing")
game.input = fakeInput("a")
screen:update(0)
eq(save.player.gender, "female", "A on Girl writes PLAYERGENDER_FEMALE")

check(type(screen.text) == "string" and screen.text:find("boy"),
  "the prompt is _AreYouABoyOrAreYouAGirlText")

-- ------------------------------------------------- the beat in Oak's speech

local function speechFor(sprites)
  return { game = { data = { gen2Sprites = sprites } } }
end

local crystalSteps = OakSpeech.defaultSteps(speechFor({ SPRITE_KRIS = {} }))
eq(crystalSteps[1].id, "gender_select",
  "PlayerProfileSetup's InitGender runs before OakSpeech")
eq(crystalSteps[1].kind, "gender", "as its own step kind")
eq(crystalSteps[2].id, "init_clock", "and the clock follows it")

local goldSteps = OakSpeech.defaultSteps(speechFor({ SPRITE_CHRIS = {} }))
eq(goldSteps[1].id, "init_clock", "Gold opens on the clock, as it always did")
for _, step in ipairs(goldSteps) do
  check(step.kind ~= "gender", "and never grows a gender beat")
end
eq(OakSpeech.defaultSteps()[1].id, "init_clock",
  "a bare call (no speech) is the Gold list")
eq(#goldSteps + 1, #crystalSteps, "the Crystal list is the Gold list plus one")

-- ------------------------------------------------- the trainer card

local CARD_GFX = {
  card = "card.png", cardFemale = "card_f.png", cardTilesWide = 16,
  leaderClasses = { "FALKNER" },
  -- the male attrmap the extractor writes: portrait on $0, corner on $1
  paletteZones = { { 14, 1, 5, 7, 1 }, { 18, 1, 1, 1, 2 } },
}

local function cardFor(gender)
  return TrainerCard.new({ data = {} }, {
    save = { player = { gender = gender, badges = {}, kantoBadges = {} } },
    menuGfx = { trainerCard = CARD_GFX },
    palettes = { trainers = { PLAYER = { { 1, 1, 1 }, { 2, 2, 2 } },
      FALKNER = { { 3, 3, 3 }, { 4, 4, 4 } } } },
  })
end

local male = cardFor("male")
check(not male.female, "Chris keeps ChrisCardPic")
eq(male.zoneDefault, 2, "and the border wears Falkner's row")
eq(male.zone[1 * 20 + 14], 1, "with the portrait on the player's")

local female = cardFor("female")
check(female.female, "Kris takes KrisCardPic")
eq(female.zoneDefault, 1, "the border swaps to Chris's row")
eq(female.zone[1 * 20 + 14], 2, "the portrait to Falkner's, which is Kris's")
eq(female.zone[1 * 20 + 18], 1, "the top-right corner follows the border")
eq(female.zone[14 * 20 + 14], 2, "and Clair borrows Kris's palette")
eq(female.zone[14 * 20 + 10], nil, "Pryce's box is untouched")

local noFemaleArt = TrainerCard.new({ data = {} }, {
  save = { player = { gender = "female" } },
  menuGfx = { trainerCard = { card = "card.png", paletteZones = {} } },
})
check(not noFemaleArt.female,
  "a Gold cache with no cardFemale draws the card it has")

-- ------------------------------------------------- the Pokegear

local GEAR_GFX = {
  tiles = "gear.png",
  palettes = { { { 1, 1, 1 } } },
  palettesFemale = { { { 9, 9, 9 } } },
}

local function gearFor(gender)
  return Pokegear.new({ data = {} }, {
    save = { player = { gender = gender }, pokegearFlags = {} },
    menuGfx = { pokegear = GEAR_GFX },
  })
end

eq(gearFor("male"):pals(), GEAR_GFX.palettes, "MalePokegearPals for Chris")
eq(gearFor("female"):pals(), GEAR_GFX.palettesFemale,
  "FemalePokegearPals for Kris")
local noFemalePals = Pokegear.new({ data = {} }, {
  save = { player = { gender = "female" }, pokegearFlags = {} },
  menuGfx = { pokegear = { tiles = "gear.png", palettes = GEAR_GFX.palettes } },
})
eq(noFemalePals:pals(), GEAR_GFX.palettes,
  "a Gold cache has one set and uses it")

-- ------------------------------------------------- the magnet train

local MagnetTrainRide = require("src.ui.gen2.MagnetTrainRide")
local SPRITES = { SPRITE_CHRIS = { image = "chris.png" },
  SPRITE_KRIS = { image = "kris.png" } }
eq(MagnetTrainRide.playerSpriteDef({ data = { gen2Sprites = SPRITES },
  gender = "female" }), SPRITES.SPRITE_KRIS, "Kris rides MAGNET_TRAIN_BLUE")
eq(MagnetTrainRide.playerSpriteDef({ data = { gen2Sprites = SPRITES },
  gender = "male" }), SPRITES.SPRITE_CHRIS, "Chris rides MAGNET_TRAIN_RED")
eq(MagnetTrainRide.playerSpriteDef({
  data = { gen2Sprites = { SPRITE_CHRIS = SPRITES.SPRITE_CHRIS } },
  gender = "female" }), SPRITES.SPRITE_CHRIS,
  "a Gold cache has only the one sheet")

-- ------------------------------------------------------------ cache-gated

local cache = os.getenv("CRYSTAL_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/crystal-dev/crystal"
end

local function loadLua(rel)
  local chunk = loadfile(cache .. "/" .. rel)
  if not chunk then return nil end
  local ok, value = pcall(chunk)
  return ok and value or nil
end

local function exists(rel)
  local f = io.open(cache .. "/" .. rel, "rb")
  if not f then return false end
  f:close()
  return true
end

local sprites = loadLua("data/generated/sprites.lua")
if not sprites then
  check(true, "crystal cache absent : SKIP")
  GameVersion.set(priorVersion)
  S.finish()
  return
end

check(sprites.SPRITE_KRIS ~= nil, "the cache carries SPRITE_KRIS")
check(sprites.SPRITE_KRIS_BIKE ~= nil, "and SPRITE_KRIS_BIKE")
eq(sprites.SPRITE_KRIS.palette, "PAL_OW_BLUE", "Kris is PAL_NPC_BLUE")
eq(sprites.SPRITE_CHRIS.palette, "PAL_OW_RED", "Chris is PAL_NPC_RED")
check(FieldMoves.hasGenderChoice(sprites),
  "so a real Crystal cache offers the choice")

for _, rel in ipairs({
  "assets/generated/intro/chris.png",
  "assets/generated/intro/kris.png",
  "assets/generated/trainer_card/card.png",
  "assets/generated/trainer_card/card_f.png",
  "assets/generated/sprites/kris.png",
  "assets/generated/sprites/kris_bike.png",
}) do
  check(exists(rel), "the cache carries " .. rel)
end

local menuGfx = loadLua("data/generated/menu_gfx.lua") or {}
check(menuGfx.trainerCard and menuGfx.trainerCard.cardFemale ~= nil,
  "menu_gfx.trainerCard.cardFemale is extracted")
check(menuGfx.pokegear and menuGfx.pokegear.palettesFemale ~= nil,
  "menu_gfx.pokegear.palettesFemale is extracted")
check(menuGfx.pack and menuGfx.pack.palettesFemale ~= nil,
  "menu_gfx.pack.palettesFemale is extracted")

local palettes = loadLua("data/generated/palettes.lua") or {}
check(palettes.trainers and palettes.trainers.PLAYER ~= nil,
  "PlayerPalette is row 0")
check(palettes.trainers and palettes.trainers.FALKNER ~= nil,
  "and KrisPalette is Falkner's")

local romText = loadLua("data/generated/rom_text.lua") or {}
check(romText._AreYouABoyOrAreYouAGirlText ~= nil,
  "the prompt is in the extracted text")

GameVersion.set(priorVersion)
S.finish()
