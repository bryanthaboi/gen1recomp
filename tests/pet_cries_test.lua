-- Pet-NPC cries: #1687 (S.S. Anne WIGGLYTUFF + MACHOKE) and #1649
-- (Vermilion PIDGEY, Vermilion City MACHOP, Fan Club PIKACHU + SEEL).
-- Commands.play_cry only arms the very next show_text, so what is asserted
-- here is placement: one play_cry row, the right species, the waitForButton
-- form, sitting immediately before the box it belongs to.  The sound itself
-- is a driver's job (tests/drivers/pet_cries_bug1687_1649_test.lua).
-- Self-contained: `luajit tests/pet_cries_test.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local init = require("data.scripts.init")
local GameVersion = require("src.core.GameVersion")
local S = require("tests.harness").suite("pet cries")
local check, eq = S.check, S.eq

local yellow = GameVersion.isYellow()

-- pokered/scripts/*.asm, PlayCry line in brackets:
--   SSAnne1FRooms.asm:66 [:70], SSAnneB1FRooms.asm:82 [:86],
--   VermilionPidgeyHouse.asm:15 [:19], VermilionCity.asm:224 [:228],
--   PokemonFanClub.asm:71 [:76] and :84 [:89],
--   MrFujisHouse.asm:56 [:60] and :63 [:67], LavenderCuboneHouse.asm:10 [:14].
local PETS = {
  { map = "SS_ANNE_1F_ROOMS", const = "TEXT_SSANNE1FROOMS_WIGGLYTUFF",
    object = "SSANNE1FROOMS_WIGGLYTUFF", species = "WIGGLYTUFF",
    label = "_SSAnne1FRoomsWigglytuffText" },
  { map = "SS_ANNE_B1F_ROOMS", const = "TEXT_SSANNEB1FROOMS_MACHOKE",
    object = "SSANNEB1FROOMS_MACHOKE", species = "MACHOKE",
    label = "_SSAnneB1FRoomsMachokeText" },
  { map = "VERMILION_PIDGEY_HOUSE", const = "TEXT_VERMILIONPIDGEYHOUSE_PIDGEY",
    object = "VERMILIONPIDGEYHOUSE_PIDGEY", species = "PIDGEY",
    label = "_VermilionPidgeyHousePidgeyText" },
  -- the cry belongs to the first box; the stomping line is a second box
  -- with no cry of its own (VermilionCity.asm:233 .StompingTheLandFlatText)
  { map = "VERMILION_CITY", const = "TEXT_VERMILIONCITY_MACHOP",
    object = "VERMILIONCITY_MACHOP", species = "MACHOP",
    label = "_VermilionCityMachopText",
    after = "_VermilionCityMachopStompingTheLandFlatText" },
  { map = "POKEMON_FAN_CLUB", const = "TEXT_POKEMONFANCLUB_SEEL",
    object = "POKEMONFANCLUB_SEEL", species = "SEEL",
    label = "_PokemonFanClubSeelText" },
  { map = "MR_FUJIS_HOUSE", const = "TEXT_MRFUJISHOUSE_PSYDUCK",
    object = "MRFUJISHOUSE_PSYDUCK", species = "PSYDUCK",
    label = "_MrFujisHousePsyduckText" },
  { map = "MR_FUJIS_HOUSE", const = "TEXT_MRFUJISHOUSE_NIDORINO",
    object = "MRFUJISHOUSE_NIDORINO", species = "NIDORINO",
    label = "_MrFujisHouseNidorinoText" },
  { map = "LAVENDER_CUBONE_HOUSE", const = "TEXT_LAVENDERCUBONEHOUSE_CUBONE",
    object = "LAVENDERCUBONEHOUSE_CUBONE", species = "CUBONE",
    label = "_LavenderCuboneHouseCuboneText" },
}

if yellow then
  PETS[#PETS + 1] = {
    map = "POKEMON_FAN_CLUB", const = "TEXT_POKEMONFANCLUB_CLEFAIRY",
    object = "POKEMONFANCLUB_CLEFAIRY", species = "CLEFAIRY",
    label = "_PokemonFanClubClefairyText",
  }
else
  PETS[#PETS + 1] = {
    map = "POKEMON_FAN_CLUB", const = "TEXT_POKEMONFANCLUB_PIKACHU",
    object = "POKEMONFANCLUB_PIKACHU", species = "PIKACHU",
    label = "_PokemonFanClubPikachuText",
  }
end

local function rowsOf(script)
  local plays, texts = {}, {}
  for i, row in ipairs(script) do
    if type(row) == "table" then
      if row[1] == "play_cry" then plays[#plays + 1] = i end
      if row[1] == "show_text" then texts[#texts + 1] = i end
    end
  end
  return plays, texts
end

for _, pet in ipairs(PETS) do
  local tag = pet.map .. "/" .. pet.const
  local script = init.talkScript(pet.map, pet.const)
  if check(type(script) == "table", tag .. " has a ported talk script") then
    local plays = rowsOf(script)
    if eq(#plays, 1, tag .. " carries exactly one play_cry row") then
      local cry = script[plays[1]]
      eq(cry[2], pet.species, tag .. " cries " .. pet.species)
      -- the waitForButton form: without it the box pops itself when the
      -- cry ends instead of holding for A/B (Commands.play_cry, #247/#251)
      eq(cry[3], true, tag .. " uses the waitForButton play_cry form")
      -- play_cry arms ctx.pendingCry for the NEXT show_text only, so the
      -- box it belongs to has to be the very next row
      local next_ = script[plays[1] + 1]
      check(type(next_) == "table" and next_[1] == "show_text"
              and next_[2] == pet.label,
            tag .. " arms " .. pet.label .. " on the next row")
    end
    if pet.after then
      local _, texts = rowsOf(script)
      eq(#texts, 2, tag .. " still shows both of its boxes")
      local last = texts[#texts]
      eq(script[last][2], pet.after, tag .. " keeps " .. pet.after .. " last")
    end
  end

  check(Data.pokemon[pet.species] ~= nil, pet.species .. " is a known species")
  check(Data.audio.cries and Data.audio.cries[pet.species] ~= nil,
        pet.species .. " has a cry program in the mounted cache")
  local text = Data.text[pet.label]
  check(type(text) == "string" and text ~= "",
        pet.label .. " resolves to text")

  -- a script nobody can reach is the same silence as a missing cry
  local objects = (Data.maps[pet.map] or {}).objects or {}
  local found
  for _, o in ipairs(objects) do
    if o.name == pet.object then found = o end
  end
  if check(found ~= nil, pet.map .. " still lists " .. pet.object) then
    eq(found.text, pet.const, pet.object .. " talks through " .. pet.const)
  end
end

-- Yellow swaps the Fan Club pet for a CLEFAIRY on its own text constant
-- (pokeyellow/data/maps/objects/PokemonFanClub.asm), so the extra row has
-- to be version-gated in both directions.
if yellow then
  check(init.talkScript("POKEMON_FAN_CLUB", "TEXT_POKEMONFANCLUB_CLEFAIRY") ~= nil,
        "Yellow registers the CLEFAIRY pet")
else
  check(init.talkScript("POKEMON_FAN_CLUB", "TEXT_POKEMONFANCLUB_CLEFAIRY") == nil,
        "Red/Blue do not register Yellow's CLEFAIRY pet")
end

-- The Yellow half of that guard, checked from any version: re-read the
-- module with isYellow forced on, then put package.loaded back exactly as
-- it was so the registry keeps pointing at the table it merged.
do
  local key = "data.scripts.flavor.pokemon_fan_club"
  local cached = package.loaded[key]
  local realIsYellow = GameVersion.isYellow
  GameVersion.isYellow = function() return true end
  package.loaded[key] = nil
  local ok, module = pcall(require, key)
  GameVersion.isYellow = realIsYellow
  package.loaded[key] = cached
  if check(ok, "the Fan Club script loads with isYellow forced on") then
    local row = module.POKEMON_FAN_CLUB.talk.TEXT_POKEMONFANCLUB_CLEFAIRY
    if check(type(row) == "table", "the Yellow branch adds the CLEFAIRY pet") then
      eq(row[1][1], "play_cry", "Yellow CLEFAIRY leads with play_cry")
      eq(row[1][2], "CLEFAIRY", "Yellow CLEFAIRY cries CLEFAIRY, not PIKACHU")
      eq(row[1][3], true, "Yellow CLEFAIRY uses the waitForButton form")
      eq(row[2][2], "_PokemonFanClubClefairyText",
         "Yellow CLEFAIRY arms its own text")
    end
  end
end

-- Sound.playCry hands PIKACHU to the PCM clips whenever the cache has
-- them, which is Yellow's voiced cry.  Red/Blue must never reach that
-- branch: audio.pikaCries is the only thing gating it.
if not yellow then
  check(Data.audio.pikaCries == nil,
        "a non-Yellow cache has no Pikachu voice clips for playCry to find")
end

S.finish()
