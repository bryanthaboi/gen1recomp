-- Importing a Gen 2 cart save (Gold, Silver, Crystal).
--   luajit tests/gen2_save_import_test.lua
-- Also dofile'd by tests/run_tests.lua.
--
-- The save this builds is synthesized rather than checked in, the same rule
-- tests/save_convert_tests.lua follows for Gen 1: a real .sav is personal
-- data. Point POKEPORT_GEN2_SAV_FIXTURE at one to run the audit at the
-- bottom against your own Gold/Silver/Crystal save.
--
-- Every offset under test comes from src/save_convert/Gen2Layout.lua, which
-- tools/gen2_sram_offsets.py generates from a pret build. The reason that
-- matters is here in miniature: Gold and Crystal disagree on almost every
-- field, so reading one with the other's table is not a near miss, it is a
-- party count of 133.
package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Gen2Save = require("src.save_convert.Gen2Save")
local Gen2Layout = require("src.save_convert.Gen2Layout")
local SaveConvert = require("src.save_convert.SaveConvert")
local FieldMoves = require("src.world.gen2.FieldMoves")

local SIZE = Gen2Save.SAVE_SIZE

-- A byte-addressable save under construction.
local function blank()
  local b = {}
  for i = 0, SIZE - 1 do b[i] = 0 end
  return b
end
local function put(b, at, ...)
  local vals = { ... }
  for i, v in ipairs(vals) do b[at + i - 1] = v % 256 end
end
local function putName(b, at, name)
  for i = 1, #name do b[at + i - 1] = 0x80 + (name:byte(i) - 65) end
  b[at + #name] = 0x50
end
local function sealOne(b, L)
  b[L.sCheckValue1] = 0x63
  b[L.sCheckValue2] = 0x7F
  local sum = 0
  for i = L.sGameData, L.sGameDataEnd - 1 do sum = (sum + b[i]) % 65536 end
  b[L.sChecksum] = sum % 256
  b[L.sChecksum + 1] = math.floor(sum / 256) % 256
end

-- A real cart seals both copies, and the game rewrites the backup from the
-- primary on every successful load.
local function seal(b, L)
  if L.backup then
    for i = 0, (L.sGameDataEnd - L.sGameData) - 1 do
      b[L.backup.sGameData + i] = b[L.sGameData + i]
    end
    sealOne(b, L.backup)
  end
  sealOne(b, L)
end
local function pack(b)
  local out = {}
  for i = 0, SIZE - 1 do out[i + 1] = string.char(b[i]) end
  return table.concat(out)
end

-- SPRITE_TWIN is $26 (constants/sprite_constants.asm:42,149,154).
local WEIRD_TREE_SLOT, SPRITE_TWIN = 4, 0x26

local function build(version, bare, female)
  local L = Gen2Save.layoutFor(version)
  local b = blank()
  putName(b, L.wPlayerName, "ASH")
  putName(b, L.wRivalName, "GARY")
  putName(b, L.wMomsName, "MOM")
  put(b, L.wPlayerID, 0x12, 0x34)          -- big-endian 0x1234
  put(b, L.wMoney, 0x01, 0xE2, 0x40)       -- 123456
  put(b, L.wBadges, 0x05)                  -- ZEPHYR + PLAIN
  put(b, L.wPartyCount, 1)
  put(b, L.wPartySpecies, 155)
  local mon = L.wPartyMons
  put(b, mon, 155)                         -- species
  put(b, mon + 1, 0)                       -- no held item
  put(b, mon + 2, 33, 43, 0, 0)            -- two moves
  put(b, mon + 0x17, 0x63, 40, 0, 0)       -- 35 PP with one PP Up, then 40
  put(b, mon + 6, 0x12, 0x34)              -- OT id
  put(b, mon + 0x15, 0x9F, 0x6A)           -- DVs: a=9 d=15 s=6 sp=10
  put(b, mon + 0x1B, 200)                  -- happiness
  put(b, mon + 0x1F, 42)                   -- level
  put(b, mon + 0x20, 0x10)                 -- BRN (bit 4)
  put(b, mon + 0x22, 0x00, 0x64)           -- hp 100
  put(b, mon + 0x24, 0x00, 0x64)           -- maxHp 100
  put(b, mon + 0x26, 0x00, 0x37)           -- attack 55
  putName(b, L.wPartyMonNicknames, "FLAME")
  putName(b, L.wPartyMonOTs, "ASH")
  put(b, L.wMapGroup, 21); put(b, L.wMapNumber, 14)
  if not bare then
    put(b, L.wStatusFlags, 0x01)           -- STATUSFLAGS_POKEDEX_F
    put(b, L.wPokegearFlags, 0x81)         -- POKEGEAR_OBTAINED_F + map card
    put(b, L.wVisitedSpawns + 1, 0x40)
    put(b, L.wVisitedSpawns + 2, 0x05)
    put(b, L.wVariableSprites + WEIRD_TREE_SLOT, SPRITE_TWIN)
    put(b, L.sceneVars.ELMS_LAB, 2)
    put(b, L.sceneVars.NEW_BARK_TOWN, 1)
    put(b, L.sceneVars.ROUTE_27, 1)
    put(b, L.sceneVars.VICTORY_ROAD, 1)
  end
  if L.wPlayerGender then put(b, L.wPlayerGender, female and 1 or 0) end
  put(b, L.wNumItems, 1); put(b, L.wItems, 20, 3); put(b, L.wItems + 2, 0xFF)
  put(b, L.wNumKeyItems, 1); put(b, L.wKeyItems, 7); put(b, L.wKeyItems + 1, 0xFF)
  put(b, L.wNumBalls, 1); put(b, L.wBalls, 5, 9); put(b, L.wBalls + 2, 0xFF)
  -- box 3, one Pokemon
  local box = L.boxes[3]
  put(b, box, 1)
  put(b, box + 0x01, 7)
  put(b, box + 0x16, 7)
  put(b, box + 0x16 + 0x1F, 15)
  putName(b, box + 0x296, "ASH")
  putName(b, box + 0x372, "SQUIRT")
  seal(b, L)
  return pack(b)
end

-- ------------------------------------------------------------------
-- What the cart holds comes back out
-- ------------------------------------------------------------------

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local save, err = Gen2Save.decode(build(version), version)
  check(save ~= nil, version .. ": a valid save decodes -- " .. tostring(err))
  if save then
    eq(save.player.name, "ASH", version .. ": player name")
    eq(save.rival.name, "GARY", version .. ": rival name")
    eq(save.player.id, 0x1234, version .. ": trainer id is big-endian")
    eq(save.player.money, 123456, version .. ": money is a 3-byte big-endian")
    eq(save.player.badges.ZEPHYR, true, version .. ": badges are keyed by name")
    eq(save.player.badges.PLAIN, true, version .. ": and the second bit too")
    eq(save.player.badges.HIVE, nil, version .. ": an unearned badge is absent")
    eq(#save.party, 1, version .. ": party size")
    local m = save.party[1]
    eq(m.species, 155, version .. ": species, uncrosswalked")
    eq(m.level, 42, version .. ": level")
    eq(m.maxHp, 100, version .. ": max hp")
    eq(m.stats.attack, 55, version .. ": computed stats come off the party tail")
    eq(#m.moves, 2, version .. ": empty move slots are dropped")
    eq(m.nickname, "FLAME", version .. ": nickname")
    eq(m.ot, "ASH", version .. ": OT name")
    eq(m.happiness, 200, version .. ": happiness")
    -- DVs are nibbles, and the HP DV is rebuilt from the other four's low bits
    eq(m.dvs.attack, 9, version .. ": attack DV is the high nibble")
    eq(m.dvs.defense, 15, version .. ": defense DV is the low nibble")
    eq(m.dvs.speed, 6, version .. ": speed DV")
    eq(m.dvs.special, 10, version .. ": special DV")
    eq(m.dvs.hp, 12, version .. ": HP DV is rebuilt, not stored")
    eq(#save.boxes, 14, version .. ": every box is present")
    eq(#save.boxes[3], 1, version .. ": box 3 holds one Pokemon")
    eq(save.boxes[3][1].species, 7, version .. ": the stored species, uncrosswalked")
    eq(save.boxes[3][1].nickname, "SQUIRT", version .. ": box nicknames follow the OTs")
    eq(save.boxes[3][1].ot, "ASH", version .. ": box OT")
    eq(save.boxes[3][1].hp, nil, version .. ": a box mon carries no computed stats")
    -- data/events/engine_flags.asm (#1900)
    eq(save.engineFlags[11], true, version .. ": ENGINE_POKEDEX out of wStatusFlags")
    eq(save.engineFlags[4], true, version .. ": ENGINE_POKEGEAR out of wPokegearFlags")
    eq(save.engineFlags[1], true, version .. ": the map card is engine flag 1")
    eq(save.engineFlags[0], nil, version .. ": the radio card bit is clear")
    local bare = assert(Gen2Save.decode(build(version, true), version))
    eq(bare.engineFlags[11], nil,
       version .. ": a save from before Mr. Pokemon's house has no dex flag")
    eq(bare.engineFlags[4], nil, version .. ": nor a POKEGEAR")

    local shift = version == "crystal" and 1 or 0
    eq(save.engineFlags[64 + shift], true, version .. ": ENGINE_FLYPOINT_NEW_BARK")
    eq(save.engineFlags[66 + shift], true, version .. ": ENGINE_FLYPOINT_VIOLET")
    eq(save.engineFlags[67 + shift], true,
       version .. ": AZALEA is bit 18, not 17 -- SPAWN_UNION_CAVE has no flag")
    eq(save.engineFlags[65 + shift], nil,
       version .. ": a town the cart never reached stays unflyable")
    eq(bare.engineFlags[64 + shift], nil,
       version .. ": and a pre-Mr.-Pokemon save has no flypoint at all")
    if shift == 0 then
      eq(FieldMoves.hasVisitedSpawn(save, "SPAWN_AZALEA"), true,
         version .. ": FLY offers the town the cart unlocked")
      eq(FieldMoves.hasVisitedSpawn(save, "SPAWN_CHERRYGROVE"), false,
         version .. ": and not the one it did not")
      eq(FieldMoves.hasVisitedSpawn(bare, "SPAWN_NEW_BARK"), false,
         version .. ": a fresh cart offers nothing")
    end

    eq(save.variableSprites[WEIRD_TREE_SLOT], SPRITE_TWIN,
       version .. ": the SPRITE_WEIRD_TREE slot comes off the cart")
    eq(save.variableSprites[0], nil,
       version .. ": a slot the cart never filled stays absent for World's seed")

    -- data/maps/scenes.asm:7
    eq(save.mapScenes.ELMS_LAB, 2, version .. ": Elm's lab is past the starter")
    eq(save.mapScenes.NEW_BARK_TOWN, 1, version .. ": the teacher no longer stops you")
    eq(save.mapScenes.ROUTE_27, 1, version .. ": the Route 27 fisher stays put")
    eq(save.mapScenes.VICTORY_ROAD, 1, version .. ": the Victory Road rival is done")
    eq(save.mapScenes.POKECENTER_2F, nil, version .. ": a zero scene byte is no entry")
    eq(next(bare.mapScenes), nil, version .. ": a fresh cart has every map on scene 0")

    -- constants/ram_constants.asm:177 (#1907)
    eq(save.player.gender, version == "crystal" and "male" or nil,
       version .. ": Gold and Silver have no gender byte to read")
    local kris = assert(Gen2Save.decode(build(version, false, true), version))
    eq(kris.player.gender, version == "crystal" and "female" or nil,
       version .. ": sCrystalData bit 0 is the imported gender")
  end
end

-- ------------------------------------------------------------------
-- The engine is keyed by name, so the codec has to translate
-- ------------------------------------------------------------------
--
-- The cart stores numbers. save.inventory holds POTION, mon.species is
-- "TYPHLOSION", data.pokemon is indexed by that name. Without this the import
-- looks perfect and the engine cannot read a byte of it.

local CROSSWALK = {
  pokemon = { CYNDAQUIL = { index = 155 }, SQUIRTLE = { index = 7 } },
  moves   = { TACKLE = { index = 33, pp = 35, name = "TACKLE" },
              LEER = { index = 43, pp = 30, name = "LEER" } },
  items   = { POTION = { index = 20 }, BICYCLE = { index = 7 },
              POKE_BALL = { index = 5 } },
  maps    = { GOLDENROD_CITY = { group = 21, map = 14 } },
}

do
  local save = assert(Gen2Save.decode(build("gold"), "gold", CROSSWALK))
  local m = save.party[1]
  eq(m.species, "CYNDAQUIL", "species is the engine's id, not the cart's number")
  eq(m.moves[1].id, "TACKLE", "and so are moves")
  eq(m.moves[2].id, "LEER", "both of them")
  -- engine/pokemon/mon_stats.asm (#1899)
  eq(m.moves[1].pp, 35, "a move slot carries the PP the cart stored")
  eq(m.moves[1].ppUps, 1, "and its PP Ups, out of the top two bits")
  eq(m.moves[1].maxPp, 42, "max PP is the base plus one PP Up's bonus")
  eq(m.pp, nil, "and there is no parallel PP array beside it")
  eq(save.boxes[3][1].species, "SQUIRTLE", "boxes translate too")

  -- One flat bag. Nothing in src reads save.keyItems or save.balls; PackMenu
  -- buckets save.inventory by each item's own pocket.
  eq(save.keyItems, nil, "there is no separate key item table")
  eq(save.balls, nil, "nor a separate ball table")
  eq(save.inventory.POTION, 3, "the ITEM pocket lands in the bag")
  eq(save.inventory.BICYCLE, 1, "so does KEY_ITEM, which is why you can cycle")
  eq(save.inventory.POKE_BALL, 9, "and BALL, which is why you can throw one")

  -- Save.summary does `save.position.map or save.spawn`, so a save with no
  -- map key resumes at the spawn point with the old coordinates.
  eq(save.position.map, "GOLDENROD_CITY", "position names the map it is on")

  -- save.pokedex.caught[species] = true, keyed the same way.
  local dexKey = next(save.pokedex.caught)
  check(dexKey == nil or type(dexKey) == "string" or type(dexKey) == "number",
    "the dex is keyed by species id")

  -- Save.scrubEvents runs tonumber over the VALUE against Save.EVENT_BYTES,
  -- and tonumber(true) is nil, so a set of booleans is silently emptied.
  eq(type(save.events[0]), "number", "events are packed bytes, not booleans")
  local evCount = 0
  for _ in pairs(save.events) do evCount = evCount + 1 end
  eq(evCount, Gen2Save.EVENT_BYTES, "one entry per event byte")

  -- 0 is truthy in Lua, so a raw status byte makes healthy mons look ill.
  eq(m.status, "brn", "status is the engine's class string")
  eq(save.boxes[3][1].status, nil, "and nil when healthy, not 0")
end

-- Without a crosswalk the raw numbers survive rather than being dropped: an id
-- this build cannot name is still the player's.
do
  local save = assert(Gen2Save.decode(build("gold"), "gold"))
  eq(save.party[1].species, 155, "an unknown species keeps its cart number")
  eq(save.party[1].moves[1].id, 33, "and an unnamed move keeps its own")
  eq(save.party[1].moves[1].maxPp, nil,
     "with no move table there is no base PP to grow a max out of")
end

-- ------------------------------------------------------------------
-- Export: what goes in comes back out, including what changed
-- ------------------------------------------------------------------
--
-- Exporting a save onto the buffer it was decoded from proves nothing: every
-- region encode does not write matches because it was copied. So this CHANGES
-- things first, in each of the places export has to reach, and reads them back
-- through a fresh decode.

do
  local ITEMS = {
    POTION      = { index = 20, pocket = "ITEM" },
    BICYCLE     = { index = 7,  pocket = "KEY_ITEM" },
    POKE_BALL   = { index = 5,  pocket = "BALL" },
    TM_HEADBUTT = { index = 191, pocket = "TM_HM", tmNumber = 2 },
  }
  local data = {
    pokemon = CROSSWALK.pokemon, moves = CROSSWALK.moves,
    items = ITEMS, maps = CROSSWALK.maps,
  }
  local cart = build("gold")
  local save = assert(Gen2Save.decode(cart, "gold", data))

  save.inventory = { POTION = 7, BICYCLE = 1, POKE_BALL = 12, TM_HEADBUTT = 1 }
  save.currentBox = 5
  save.party[1].status, save.party[1].statusTurns = "slp", 3
  save.party[1].pokerus = 0x34
  save.party[1].caughtData = 0x1234
  save.events[9] = 0xA5
  save.party[1].moves[1].pp = 12
  save.engineFlags[11] = nil
  save.engineFlags[66] = nil
  save.engineFlags[69] = true
  save.variableSprites[6] = 0x35
  save.mapScenes.ELMS_LAB = 6
  save.mapScenes.NEW_BARK_TOWN = 0
  save.mapScenes.MAHOGANY_TOWN = 1

  local out = assert(Gen2Save.encode(save, "gold", cart, data))
  eq(#out, #cart, "the image keeps its size")
  local back = assert(Gen2Save.decode(out, "gold", data))

  -- The bag: encode used to leave it at whatever the template carried, so a
  -- potion bought in a session never reached the cartridge.
  eq(back.inventory.POTION, 7, "the ITEM pocket is written")
  eq(back.inventory.BICYCLE, 1, "and KEY_ITEM")
  eq(back.inventory.POKE_BALL, 12, "and BALL")
  eq(back.inventory.TM_HEADBUTT, 1, "and TM_HM, by its tmNumber")
  eq(back.currentBox, 5, "the open box is written")

  -- 0x1C-0x1E are the mon's, not the slot's: left to the template, reordering
  -- the party gives slot 1 the previous occupant's pokerus and caught data.
  eq(back.party[1].pokerus, 0x34, "pokerus rides the mon")
  eq(back.party[1].caughtData, 0x1234, "so does caught data")

  eq(back.party[1].status, "slp", "status survives as a class")
  eq(back.party[1].statusTurns, 3, "with its turn count")
  eq(back.events[9], 0xA5, "event bytes are written")

  eq(back.party[1].moves[1].id, "TACKLE", "a move slot survives the round trip")
  eq(back.party[1].moves[1].pp, 12, "with the PP it was spent down to")
  eq(back.party[1].moves[1].ppUps, 1, "and its PP Ups still in the top bits")
  -- engine/menus/save.asm
  eq(back.engineFlags[11], nil, "a cleared engine flag clears its SRAM bit")
  eq(back.engineFlags[4], true, "and the ones left alone stay set")

  -- engine/pokegear/pokegear.asm:2189 (#1906)
  eq(back.engineFlags[66], nil, "a cleared flypoint clears its wVisitedSpawns bit")
  eq(back.engineFlags[69], true, "and a newly earned one is written")
  eq(back.engineFlags[64], true, "with the neighbours on either side untouched")
  eq(back.engineFlags[67], true, "AZALEA included, across the UNION_CAVE hole")

  -- engine/overworld/scripting.asm:869 (#1905)
  eq(back.variableSprites[WEIRD_TREE_SLOT], SPRITE_TWIN,
     "the twins' slot survives the round trip")
  eq(back.variableSprites[6], 0x35, "and a slot filled inside the port is written")

  -- data/maps/scenes.asm:7
  eq(back.mapScenes.ELMS_LAB, 6, "a scene advanced in the port is written")
  eq(back.mapScenes.NEW_BARK_TOWN, nil, "a cleared scene clears the cart byte")
  eq(back.mapScenes.MAHOGANY_TOWN, 1, "and a newly set one reaches the cart")
  eq(back.mapScenes.ROUTE_27, 1, "with the untouched ones left as they were")

  local again = assert(Gen2Save.encode(back, "gold", out, data))
  local L = Gen2Save.layoutFor("gold")
  local startAt, stopAt = L.sceneVars.POKECENTER_2F, L.sceneVars.MOUNT_MOON_SQUARE
  eq(again:sub(startAt + 1, stopAt + 1), out:sub(startAt + 1, stopAt + 1),
     "import, export, import gives the same scene bytes")

  back.mapScenes = {}
  local untouched = assert(Gen2Save.encode(back, "gold", out, data))
  eq(untouched:byte(L.sceneVars.ELMS_LAB + 1), 6,
     "a save with no scene entries leaves the cart's scene bytes alone")
end

-- ram/sram.asm:138-144
do
  eq(Gen2Layout.goldSilver.wPlayerGender, nil,
     "Gold and Silver have no gender byte")
  eq(Gen2Layout.crystal.wPlayerGender, Gen2Layout.crystal.backup.wPlayerGender,
     "the Crystal backup shares the primary's gender byte")

  local cart = build("crystal", false, true)
  local save = assert(Gen2Save.decode(cart, "crystal"))
  eq(save.player.gender, "female", "Kris imports as Kris")
  local out = assert(Gen2Save.encode(save, "crystal", cart))
  eq(out:byte(Gen2Layout.crystal.wPlayerGender + 1) % 2, 1,
     "and exports back into sCrystalData bit 0")

  save.player.gender = "male"
  local male = assert(Gen2Save.encode(save, "crystal", cart))
  eq(male:byte(Gen2Layout.crystal.wPlayerGender + 1) % 2, 0,
     "a gender changed in the port reaches the cart image")
  eq(assert(Gen2Save.decode(male, "crystal")).player.gender, "male",
     "and reads back as Chris")
end

-- data/maps/scenes.asm:7
do
  local function shape(L, want, label)
    local n = 0
    for mapId, at in pairs(L.sceneVars) do
      n = n + 1
      check(at >= L.sGameData and at < L.sGameDataEnd,
        ("%s: %s scene byte 0x%04X is inside the checksummed block"):format(label, mapId, at))
    end
    eq(n, want, label .. ": one scene byte per scene_var row")
  end
  shape(Gen2Layout.goldSilver, 59, "gold/silver")
  shape(Gen2Layout.crystal, 79, "crystal")
  shape(Gen2Layout.crystal.backup, 79, "crystal backup")
  eq(Gen2Layout.goldSilver.sceneVars.ELMS_LAB, 0x2534, "gold wElmsLabSceneID")
  eq(Gen2Layout.crystal.sceneVars.ELMS_LAB, 0x2515, "crystal wElmsLabSceneID")
  eq(Gen2Layout.crystal.backup.sceneVars.ELMS_LAB,
     Gen2Layout.crystal.sceneVars.ELMS_LAB - 0xE00, "the backup copy is the same byte shifted")
end

-- engine/pokemon/stats_screen.asm (#1899)

do
  local SummaryMenu = require("src.ui.gen2.SummaryMenu")
  local save = assert(Gen2Save.decode(build("gold"), "gold", CROSSWALK))
  local view = setmetatable(
    { mon = save.party[1], moves = CROSSWALK.moves, items = CROSSWALK.items,
      party = {}, page = SummaryMenu.GREEN_PAGE },
    { __index = SummaryMenu })
  local rows = {}
  for _, row in ipairs(view:greenPlacements()) do
    rows[#rows + 1] = row.text
  end
  local text = table.concat(rows, "|")
  check(text:find("TACKLE", 1, true) ~= nil,
    "the green page names the imported move -- got: " .. text)
  check(text:find("35", 1, true) ~= nil and text:find("42", 1, true) ~= nil,
    "and prints its PP over its max rather than 0/ 0 -- got: " .. text)
end

-- engine/menus/start_menu.asm (#1900)
do
  local StartMenu = require("src.ui.gen2.StartMenu")
  local imported = assert(SaveConvert.importSav(build("gold"), "gold", "gold"))
  local menu = setmetatable({ save = imported }, { __index = StartMenu })
  local rows = {}
  for _, item in ipairs(menu:visibleItems()) do rows[#rows + 1] = item.value end
  local list = table.concat(rows, ",")
  check(list:find("pokedex", 1, true) ~= nil,
    "an imported save shows #DEX on the START menu -- got: " .. list)
  check(list:find("pokegear", 1, true) ~= nil,
    "and the POKEGEAR row too -- got: " .. list)

  local before = assert(SaveConvert.importSav(build("gold", true), "gold", "gold"))
  local early = setmetatable({ save = before }, { __index = StartMenu })
  local earlyRows = {}
  for _, item in ipairs(early:visibleItems()) do earlyRows[#earlyRows + 1] = item.value end
  check(table.concat(earlyRows, ","):find("pokedex", 1, true) == nil,
    "and a save from before the dex was given still hides it")
end

-- A save with no cartridge image behind it is refused, not invented.
do
  local out, err = Gen2Save.encode({ player = { name = "A" } }, "gold", nil, {})
  eq(out, nil, "encode refuses a save with no lineage")
  check(type(err) == "string" and err:find("no cartridge image", 1, true) ~= nil,
    "and says why -- " .. tostring(err))
end

-- ------------------------------------------------------------------
-- A save the real cartridge would open must not be refused
-- ------------------------------------------------------------------
--
-- TryLoadSaveFile checks the primary, and on failure VerifyBackupChecksum and
-- LoadBackupPlayerData. Refusing on the primary alone reports a save the game
-- itself would load as corrupt, which is what #1832 was about.

do
  local L = Gen2Save.layoutFor("crystal")
  check(L.backup ~= nil, "Crystal carries a backup layout")
  eq(Gen2Save.layoutFor("gold").backup, nil,
    "Gold and Silver split theirs across three sections, so they have none")

  local good = build("crystal")
  local at = L.sChecksum + 1
  local broken = good:sub(1, at - 1)
    .. string.char((good:byte(at) + 1) % 256) .. good:sub(at + 1)

  eq(Gen2Save.checksumValid(broken, L), false, "the primary is now corrupt")
  eq(Gen2Save.checksumValid(broken, L.backup), true, "the backup is not")
  local save, err = Gen2Save.decode(broken, "crystal")
  check(save ~= nil, "so the save still opens -- " .. tostring(err))
  if save then
    eq(save.player.name, "ASH", "and reads the same player out of the backup")
    eq(save.mapScenes.ELMS_LAB, 2, "and the same map scenes out of the backup")
  end
end

-- ------------------------------------------------------------------
-- Gold's table is not Crystal's
-- ------------------------------------------------------------------

do
  local goldBytes = build("gold")
  local wrong, err = Gen2Save.decode(goldBytes, "crystal")
  check(wrong == nil, "a Gold save read with Crystal's table is refused")
  check(type(err) == "string" and err:find("checksum", 1, true) ~= nil,
    "and refused by the guard, not by luck -- got: " .. tostring(err))
  check(Gen2Layout.goldSilver.wPartyMons ~= Gen2Layout.crystal.wPartyMons,
    "the two layouts really do disagree about where the party is")
end

-- ------------------------------------------------------------------
-- Through the launcher's own entry point
-- ------------------------------------------------------------------

do
  local save, err = SaveConvert.importSav(build("gold"), "gold", "gold")
  check(save ~= nil, "importSav accepts a Gen 2 save now -- " .. tostring(err))
  if save then
    eq(save.player.name, "ASH", "and returns the decoded player")
    eq(save.generation, 2, "tagged as Gen 2")
    -- Everything the cart does not carry still has to be there.
    check(type(save.mail) == "table", "mail falls back to the new-game default")
    check(type(save.hallOfFame) == "table", "so does the hall of fame")
    check(type(save.phoneContacts) == "table", "and the phone book")
    eq(save.mapScenes.ELMS_LAB, 2, "and the cart's map scenes survive the merge")
  end
  -- Export needs the cartridge image the save came from. Without one it is
  -- refused rather than built from nothing.
  local _, expErr = SaveConvert.exportSav({ meta = {} }, "gold")
  check(type(expErr) == "string" and expErr:find("no cartridge image", 1, true) ~= nil,
    "a save with no cartridge behind it is refused -- got: " .. tostring(expErr))
end

-- ------------------------------------------------------------------
-- Real-save audit (fixture-gated)
-- ------------------------------------------------------------------

local fixture = os.getenv("POKEPORT_GEN2_SAV_FIXTURE")
local fixtureVersion = os.getenv("POKEPORT_GEN2_SAV_VERSION") or "crystal"
if not fixture then
  print("real-save audit skipped (set POKEPORT_GEN2_SAV_FIXTURE to a Gen 2 .sav, "
    .. "and POKEPORT_GEN2_SAV_VERSION to gold/silver/crystal)")
else
  local f = io.open(fixture, "rb")
  local bytes = f and f:read("*a")
  if f then f:close() end
  check(bytes ~= nil, "the fixture is readable")
  if bytes then
    local save, err = Gen2Save.decode(bytes, fixtureVersion)
    check(save ~= nil, "a real cart save decodes -- " .. tostring(err))
    if save then
      check(#save.party >= 1 and #save.party <= 6, "party size is possible")
      check(#save.player.name > 0, "the player has a name")
      for i, mon in ipairs(save.party) do
        check(mon.species >= 1 and mon.species <= Gen2Save.NUM_SPECIES,
          ("party %d species is a real species (%d)"):format(i, mon.species))
        check(mon.level >= 1 and mon.level <= 100,
          ("party %d level is possible (%d)"):format(i, mon.level))
        check(mon.dvs.attack <= 15 and mon.dvs.special <= 15,
          ("party %d DVs are nibbles"):format(i))
      end
      for b, box in ipairs(save.boxes) do
        check(#box <= Gen2Save.BOX_CAPACITY, ("box %d holds at most 20"):format(b))
      end

      -- And back out. Without the item table the bag cannot be bucketed, so
      -- this asserts the refusal rather than a lossy write.
      local out, err = Gen2Save.encode(save, fixtureVersion, bytes, {})
      if out then
        eq(#out, #bytes, "the exported image keeps the cart's size, RTC and all")
        local back = assert(Gen2Save.decode(out, fixtureVersion))
        eq(back.player.name, save.player.name, "the player survives the round trip")
        eq(#back.party, #save.party, "and the party")
        local a, b2 = 0, 0
        for _, box in ipairs(save.boxes) do a = a + #box end
        for _, box in ipairs(back.boxes) do b2 = b2 + #box end
        eq(b2, a, "and every stored Pokemon")
      else
        check(err:find("pocket", 1, true) ~= nil,
          "or it refuses because the bag cannot be sorted -- " .. tostring(err))
      end
    end
  end
end

T.finish()
